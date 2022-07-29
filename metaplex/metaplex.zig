const std = @import("std");
const sol = @import("sol");

pub const token_metadata = @import("token_metadata.zig");

pub const token_metadata_program_id = sol.PublicKey.comptimeFromBase58("metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s");

test {
    std.testing.refAllDecls(@This());
}
