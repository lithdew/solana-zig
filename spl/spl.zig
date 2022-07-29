const std = @import("std");
const sol = @import("sol");

pub const token = @import("token.zig");
pub const associated_token = @import("associated_token.zig");

pub const token_program_id = sol.PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
pub const associated_token_program_id = sol.PublicKey.comptimeFromBase58("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL");

test {
    std.testing.refAllDecls(@This());
}
