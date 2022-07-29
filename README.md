# solana-zig

## Setup

1. Add this repository as a submodule to your project:

```console
git submodule init
git submodule add https://github.com/lithdew/solana-zig.git sol
git submodule update --init --recursive
```

2. In build.zig:

```zig
const std = @import("std");
const sol = @import("sol/build.zig");

// Assume 'step' is a *std.build.LibExeObjStep, and 'sol/' is the directory in
// which this repository is located within your project.

const sol_pkgs = sol.Packages("sol/");

inline for (@typeInfo(sol_pkgs).Struct.decls) |field| {
    step.addPackage(@field(sol_pkgs, field.name));
}
```

## Example

1. Setup build.zig:

```zig
const std = @import("std");
const sol = @import("sol/build.zig");

const sol_pkgs = sol.Packages("sol/");

pub fn build(b: *std.build.Builder) !void {
    const program = b.addSharedLibrary("helloworld", "main.zig", .unversioned);
    inline for (@typeInfo(sol_pkgs).Struct.decls) |field| {
        program.addPackage(@field(sol_pkgs, field.name));
    }
    program.install();

    try sol.linkSolanaProgram(b, program);
    try sol.generateProgramKeypair(b, program);
}
```

2. Setup main.zig:

```zig
const sol = @import("sol");

export fn entrypoint(_: [*]u8) callconv(.C) u64 {
    sol.print("Hello world!", .{});
    return 0;
}
```

3. Build and deploy your program on Solana devnet:

```console
$ zig build
Program ID: FHGeakPPYgDWomQT6Embr4mVW5DSoygX6TaxQXdgwDYU

$ solana airdrop -ud 1
Requesting airdrop of 1 SOL

Signature: 52rgcLosCjRySoQq5MQLpoKg4JacCdidPNXPWbJhTE1LJR2uzFgp93Q7Dq1hQrcyc6nwrNrieoN54GpyNe8H4j3T

882.4039166 SOL

$ solana program deploy -ud zig-out/lib/libhelloworld.so
Program Id: FHGeakPPYgDWomQT6Embr4mVW5DSoygX6TaxQXdgwDYU
```