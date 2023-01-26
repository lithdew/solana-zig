const std = @import("std");

pub fn generateProgramKeypair(b: *std.build.Builder, lib: *std.build.LibExeObjStep) !void {
    const base58 = @import("base58/base58.zig");

    const path = b.fmt("{s}-keypair.json", .{lib.out_filename[0 .. lib.out_filename.len - std.fs.path.extension(lib.out_filename).len]});
    const absolute_path = b.getInstallPath(.lib, path);

    if (std.fs.openFileAbsolute(absolute_path, .{})) |keypair_file| {
        const keypair_json = try keypair_file.readToEndAlloc(b.allocator, 1 * 1024 * 1024);
        var keypair_json_token_stream = std.json.TokenStream.init(keypair_json);

        const keypair_secret = try std.json.parse([std.crypto.sign.Ed25519.SecretKey.encoded_length]u8, &keypair_json_token_stream, .{});
        const keypair = try std.crypto.sign.Ed25519.KeyPair.fromSecretKey(try std.crypto.sign.Ed25519.SecretKey.fromBytes(keypair_secret));

        var program_id_buffer: [base58.bitcoin.getEncodedLengthUpperBound(std.crypto.sign.Ed25519.PublicKey.encoded_length)]u8 = undefined;
        const program_id = base58.bitcoin.encode(&program_id_buffer, &keypair.public_key.bytes);

        const log = b.addLog("Program ID: {s}", .{program_id});
        b.getInstallStep().dependOn(&log.step);
    } else |err| {
        if (err != std.fs.File.OpenError.FileNotFound) {
            return err;
        }

        const program_keypair = try std.crypto.sign.Ed25519.KeyPair.create(null);

        var keypair_json = std.ArrayList(u8).init(b.allocator);
        try std.json.stringify(program_keypair.secret_key.bytes, .{}, keypair_json.writer());

        const keypair = b.addWriteFile(path, keypair_json.items);
        b.getInstallStep().dependOn(&keypair.step);

        const install_keypair = b.addInstallLibFile(keypair.getFileSource(path).?, path);
        b.getInstallStep().dependOn(&install_keypair.step);

        var program_id_buffer: [base58.bitcoin.getEncodedLengthUpperBound(std.crypto.sign.Ed25519.PublicKey.encoded_length)]u8 = undefined;
        const program_id = base58.bitcoin.encode(&program_id_buffer, &program_keypair.public_key.bytes);

        const log = b.addLog("Program ID: {s}", .{program_id});
        b.getInstallStep().dependOn(&log.step);
    }
}

pub fn Packages(comptime base_dir: []const u8) type {
    return struct {
        pub const base58 = std.build.Pkg{
            .name = "base58",
            .source = .{ .path = base_dir ++ "base58/base58.zig" },
        };

        pub const bincode = std.build.Pkg{
            .name = "bincode",
            .source = .{ .path = base_dir ++ "bincode/bincode.zig" },
        };

        pub const borsh = std.build.Pkg{
            .name = "borsh",
            .source = .{ .path = base_dir ++ "borsh/borsh.zig" },
        };

        pub const sol = std.build.Pkg{
            .name = "sol",
            .source = .{ .path = base_dir ++ "sol.zig" },
            .dependencies = &.{
                base58,
                bincode,
            },
        };

        pub const spl = std.build.Pkg{
            .name = "spl",
            .source = .{ .path = base_dir ++ "spl/spl.zig" },
            .dependencies = &.{
                sol,
                bincode,
            },
        };

        pub const metaplex = std.build.Pkg{
            .name = "metaplex",
            .source = .{ .path = base_dir ++ "metaplex/metaplex.zig" },
            .dependencies = &.{
                sol,
                borsh,
            },
        };
    };
}

pub fn linkSolanaProgram(b: *std.build.Builder, lib: *std.build.LibExeObjStep) !void {
    const linker_script = b.addWriteFile("bpf.ld",
        \\PHDRS
        \\{
        \\text PT_LOAD  ;
        \\rodata PT_LOAD ;
        \\dynamic PT_DYNAMIC ;
        \\}
        \\
        \\SECTIONS
        \\{
        \\. = SIZEOF_HEADERS;
        \\.text : { *(.text*) } :text
        \\.rodata : { *(.rodata*) } :rodata
        \\.data.rel.ro : { *(.data.rel.ro*) } :rodata
        \\.dynamic : { *(.dynamic) } :dynamic
        \\}
    );

    lib.step.dependOn(&linker_script.step);

    lib.setTarget(.{
        .cpu_arch = .bpfel,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.bpf.featureSet(&.{.solana}),
    });

    lib.stack_size = 4096;

    lib.linker_script = linker_script.getFileSource("bpf.ld");
    lib.entry_symbol_name = "entrypoint";
    lib.force_pic = true;
    lib.strip = true;
    lib.link_z_notext = true;
    lib.build_mode = .ReleaseFast;
}
