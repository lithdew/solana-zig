const std = @import("std");
const base58 = @import("base58");
const builtin = @import("builtin");

const sol = @import("sol.zig");

const mem = std.mem;
const testing = std.testing;

pub const ProgramDerivedAddress = struct {
    address: PublicKey,
    bump_seed: [1]u8,
};

pub const PublicKey = extern struct {
    pub const length: usize = 32;
    pub const base58_length: usize = 44;

    pub const max_num_seeds: usize = 16;
    pub const max_seed_length: usize = 32;

    bytes: [PublicKey.length]u8,

    pub fn from(bytes: [PublicKey.length]u8) PublicKey {
        return .{ .bytes = bytes };
    }

    pub fn comptimeFromBase58(comptime encoded: []const u8) PublicKey {
        return PublicKey.from(base58.bitcoin.comptimeDecode(encoded));
    }

    pub fn comptimeCreateProgramAddress(comptime seeds: anytype, comptime program_id: PublicKey) PublicKey {
        comptime {
            return PublicKey.createProgramAddress(seeds, program_id) catch |err| {
                @compileError("Failed to create program address: " ++ @errorName(err));
            };
        }
    }

    pub fn comptimeFindProgramAddress(comptime seeds: anytype, comptime program_id: PublicKey) ProgramDerivedAddress {
        comptime {
            return PublicKey.findProgramAddress(seeds, program_id) catch |err| {
                @compileError("Failed to find program address: " ++ @errorName(err));
            };
        }
    }

    pub fn equals(self: PublicKey, other: PublicKey) bool {
        return mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn isPointOnCurve(self: PublicKey) bool {
        const Y = std.crypto.ecc.Curve25519.Fe.fromBytes(self.bytes);
        const Z = std.crypto.ecc.Curve25519.Fe.one;
        const YY = Y.sq();
        const u = YY.sub(Z);
        const v = YY.mul(std.crypto.ecc.Curve25519.Fe.edwards25519d).add(Z);
        if (sqrtRatioM1(u, v) != 1) {
            return false;
        }
        return true;
    }

    fn sqrtRatioM1(u: std.crypto.ecc.Curve25519.Fe, v: std.crypto.ecc.Curve25519.Fe) u32 {
        const v3 = v.sq().mul(v); // v^3
        const x = v3.sq().mul(u).mul(v).pow2523().mul(v3).mul(u); // uv^3(uv^7)^((q-5)/8)
        const vxx = x.sq().mul(v); // vx^2
        const m_root_check = vxx.sub(u); // vx^2-u
        const p_root_check = vxx.add(u); // vx^2+u
        const has_m_root = m_root_check.isZero();
        const has_p_root = p_root_check.isZero();
        return @boolToInt(has_m_root) | @boolToInt(has_p_root);
    }

    pub fn createProgramAddress(seeds: anytype, program_id: PublicKey) !PublicKey {
        if (seeds.len > PublicKey.max_num_seeds) {
            return error.MaxSeedLengthExceeded;
        }

        comptime var seeds_index = 0;
        inline while (seeds_index < seeds.len) : (seeds_index += 1) {
            if (@as([]const u8, seeds[seeds_index]).len > PublicKey.max_seed_length) {
                return error.MaxSeedLengthExceeded;
            }
        }

        var address: PublicKey = undefined;

        if (sol.is_bpf_program) {
            const Syscall = struct {
                extern fn sol_create_program_address(
                    seeds_ptr: [*]const []const u8,
                    seeds_len: u64,
                    program_id_ptr: *const PublicKey,
                    address_ptr: *PublicKey,
                ) callconv(.C) u64;
            };

            var seeds_array: [seeds.len][]const u8 = undefined;
            inline for (seeds) |seed, i| seeds_array[i] = seed;

            const result = Syscall.sol_create_program_address(
                &seeds_array,
                seeds.len,
                &program_id,
                &address,
            );
            if (result != 0) {
                sol.print("failed to create program address with seeds {any} and program id {}: error code {}", .{
                    seeds,
                    program_id,
                    result,
                });
                return error.Unexpected;
            }

            return address;
        }

        @setEvalBranchQuota(100_000_000);

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        comptime var i = 0;
        inline while (i < seeds.len) : (i += 1) {
            hasher.update(seeds[i]);
        }
        hasher.update(&program_id.bytes);
        hasher.update("ProgramDerivedAddress");
        hasher.final(&address.bytes);

        if (address.isPointOnCurve()) {
            return error.InvalidSeeds;
        }

        return address;
    }

    pub fn findProgramAddress(seeds: anytype, program_id: PublicKey) !ProgramDerivedAddress {
        var pda: ProgramDerivedAddress = undefined;

        if (comptime sol.is_bpf_program) {
            const Syscall = struct {
                extern fn sol_try_find_program_address(
                    seeds_ptr: [*]const []const u8,
                    seeds_len: u64,
                    program_id_ptr: *const PublicKey,
                    address_ptr: *PublicKey,
                    bump_seed_ptr: *u8,
                ) callconv(.C) u64;
            };

            var seeds_array: [seeds.len][]const u8 = undefined;

            comptime var seeds_index = 0;
            inline while (seeds_index < seeds.len) : (seeds_index += 1) {
                const Seed = @TypeOf(seeds[seeds_index]);
                if (comptime std.meta.trait.isZigString(Seed)) {
                    seeds_array[seeds_index] = seeds[seeds_index];
                } else if (comptime Seed == PublicKey) {
                    seeds_array[seeds_index] = &seeds[seeds_index].bytes;
                } else {
                    @compileError("Unknown seed type '" ++ @typeName(Seed) ++ "'");
                }
            }

            const result = Syscall.sol_try_find_program_address(
                &seeds_array,
                seeds.len,
                &program_id,
                &pda.address,
                &pda.bump_seed[0],
            );
            if (result != 0) {
                sol.print("failed to find program address given seeds {any} and program id {}: error code {}", .{
                    seeds,
                    program_id,
                    result,
                });
                return error.Unexpected;
            }

            return pda;
        }

        var seeds_with_bump: [seeds.len + 1][]const u8 = undefined;

        comptime var seeds_index = 0;
        inline while (seeds_index < seeds.len) : (seeds_index += 1) {
            const Seed = @TypeOf(seeds[seeds_index]);
            if (comptime std.meta.trait.isZigString(Seed)) {
                seeds_with_bump[seeds_index] = seeds[seeds_index];
            } else if (comptime Seed == PublicKey) {
                seeds_with_bump[seeds_index] = &seeds[seeds_index].bytes;
            } else {
                @compileError("Unknown seed type '" ++ @typeName(Seed) ++ "'");
            }
        }

        pda.bump_seed[0] = 255;
        seeds_with_bump[seeds.len] = &pda.bump_seed;

        while (pda.bump_seed[0] >= 0) : (pda.bump_seed[0] -= 1) {
            pda = ProgramDerivedAddress{
                .address = PublicKey.createProgramAddress(&seeds_with_bump, program_id) catch {
                    if (pda.bump_seed[0] == 0) {
                        return error.NoViableBumpSeed;
                    }
                    continue;
                },
                .bump_seed = pda.bump_seed,
            };

            break;
        }

        return pda;
    }

    pub fn jsonStringify(self: PublicKey, options: anytype, writer: anytype) !void {
        _ = options;
        try writer.print("\"{}\"", .{self});
    }

    pub fn format(self: PublicKey, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        var buffer: [base58.bitcoin.getEncodedLengthUpperBound(PublicKey.length)]u8 = undefined;
        try writer.print("{s}", .{base58.bitcoin.encode(&buffer, &self.bytes)});
    }
};

// TODO(kenta): fix tests
// test "public_key: comptime create program address" {
//     const address = PublicKey.comptimeCreateProgramAddress(.{ "hello", &.{255} }, sol.system_program_id);
//     try testing.expectFmt("2PjSSVURwJV4o9wz1BDVwwddvcUCuF1NKFpcQBF9emYJ", "{}", .{address});
// }

// test "public_key: comptime find program address" {
//     const pda = PublicKey.comptimeFindProgramAddress(.{"hello"}, sol.system_program_id);
//     try testing.expectFmt("2PjSSVURwJV4o9wz1BDVwwddvcUCuF1NKFpcQBF9emYJ", "{}", .{pda.address});
//     try testing.expectEqual(@as(u8, 255), pda.bump_seed[0]);
// }
