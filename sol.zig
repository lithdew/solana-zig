const std = @import("std");
const builtin = @import("builtin");

const sol = @This();

pub usingnamespace @import("public_key.zig");
pub usingnamespace @import("account.zig");
pub usingnamespace @import("instruction.zig");
pub usingnamespace @import("allocator.zig");
pub usingnamespace @import("context.zig");
pub usingnamespace @import("build.zig");
pub usingnamespace @import("clock.zig");
pub usingnamespace @import("rent.zig");

pub const SystemProgram = @import("SystemProgram.zig");

pub const bpf = @import("bpf.zig");

pub const is_bpf_program = !builtin.is_test and
    builtin.os.tag == .freestanding and
    builtin.cpu.arch == .bpfel and
    std.Target.bpf.featureSetHas(builtin.cpu.features, .solana);

pub const native_loader_id = sol.PublicKey.comptimeFromBase58("NativeLoader1111111111111111111111111111111");
pub const system_program_id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");
pub const incinerator_id = sol.PublicKey.comptimeFromBase58("1nc1nerator11111111111111111111111111111111");

pub const rent_id = sol.PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
pub const clock_id = sol.PublicKey.comptimeFromBase58("SysvarC1ock11111111111111111111111111111111");
pub const sysvar_id = sol.PublicKey.comptimeFromBase58("Sysvar1111111111111111111111111111111111111");

pub const ed25519_program_id = sol.PublicKey.comptimeFromBase58("Ed25519SigVerify111111111111111111111111111");
pub const secp256k1_program_id = sol.PublicKey.comptimeFromBase58("KeccakSecp256k11111111111111111111111111111");

pub const bpf_loader_deprecated_program_id = sol.PublicKey.comptimeFromBase58("BPFLoader1111111111111111111111111111111111");
pub const bpf_loader_program_id = sol.PublicKey.comptimeFromBase58("BPFLoader2111111111111111111111111111111111");
pub const bpf_upgradeable_loader_program_id = sol.PublicKey.comptimeFromBase58("BPFLoaderUpgradeab1e11111111111111111111111");

pub const lamports_per_sol = 1_000_000_000;

pub inline fn log(message: []const u8) void {
    if (sol.is_bpf_program) {
        const Syscall = struct {
            extern fn sol_log_(ptr: [*]const u8, len: u64) callconv(.C) void;
        };
        Syscall.sol_log_(message.ptr, message.len);
    } else {
        std.debug.print("{s}\n", .{message});
    }
}

pub fn print(comptime format: []const u8, args: anytype) void {
    if (!sol.is_bpf_program) {
        return std.debug.print(format ++ "\n", args);
    }

    if (args.len == 0) {
        return log(format);
    }

    const message = std.fmt.allocPrint(sol.allocator, format, args) catch return;
    defer sol.allocator.free(message);

    return sol.log(message);
}

test {
    std.testing.refAllDecls(@This());
}
