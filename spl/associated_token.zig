const std = @import("std");
const sol = @import("sol");
const bincode = @import("bincode");

const spl = @import("spl.zig");

const associated_token = @This();

pub const Instruction = union(enum(u8)) {
    /// Creates an associated token account for the given wallet address and token mint
    /// Returns an error if the account exists.
    ///
    ///   0. `[writeable,signer]` Funding account (must be a system account)
    ///   1. `[writeable]` Associated token account address to be created
    ///   2. `[]` Wallet address for the new associated token account
    ///   3. `[]` The token mint for the new associated token account
    ///   4. `[]` System program
    ///   5. `[]` SPL Token program
    create: void,
    /// Creates an associated token account for the given wallet address and token mint,
    /// if it doesn't already exist.  Returns an error if the account exists,
    /// but with a different owner.
    ///
    ///   0. `[writeable,signer]` Funding account (must be a system account)
    ///   1. `[writeable]` Associated token account address to be created
    ///   2. `[]` Wallet address for the new associated token account
    ///   3. `[]` The token mint for the new associated token account
    ///   4. `[]` System program
    ///   5. `[]` SPL Token program
    create_idempotent: void,
    /// Transfers from and closes a nested associated token account: an
    /// associated token account owned by an associated token account.
    ///
    /// The tokens are moved from the nested associated token account to the
    /// wallet's associated token account, and the nested account lamports are
    /// moved to the wallet.
    ///
    /// Note: Nested token accounts are an anti-pattern, and almost always
    /// created unintentionally, so this instruction should only be used to
    /// recover from errors.
    ///
    ///   0. `[writeable]` Nested associated token account, must be owned by `3`
    ///   1. `[]` Token mint for the nested associated token account
    ///   2. `[writeable]` Wallet's associated token account
    ///   3. `[]` Owner associated token account address, must be owned by `5`
    ///   4. `[]` Token mint for the owner associated token account
    ///   5. `[writeable, signer]` Wallet address for the owner associated token account
    ///   6. `[]` SPL Token program
    recover_nested: void,
};

pub fn getAccountId(mint_id: sol.PublicKey, user_id: sol.PublicKey) !sol.PublicKey {
    const pda = try associated_token.getAccountPDA(mint_id, user_id);
    return pda.address;
}

pub fn getAccountPDA(mint_id: sol.PublicKey, user_id: sol.PublicKey) !sol.ProgramDerivedAddress {
    return sol.PublicKey.findProgramAddress(.{ user_id, spl.token_program_id, mint_id }, spl.associated_token_program_id);
}

pub fn createAccount(account: sol.Account.Info, params: struct {
    funder: sol.Account.Info,
    owner: sol.Account.Info,
    mint: sol.Account.Info,
    system_program: sol.Account.Info,
    token_program: sol.Account.Info,
    rent: sol.Account.Info,
    seeds: []const []const []const u8 = &.{},
}) !void {
    const data = try bincode.writeAlloc(sol.allocator, associated_token.Instruction.create, .{});
    defer sol.allocator.free(data);

    const instruction = sol.Instruction.from(.{
        .program_id = &spl.associated_token_program_id,
        .accounts = &[_]sol.Account.Param{
            .{ .id = params.funder.id, .is_writable = true, .is_signer = true },
            .{ .id = account.id, .is_writable = true, .is_signer = false },
            .{ .id = params.owner.id, .is_writable = false, .is_signer = false },
            .{ .id = params.mint.id, .is_writable = false, .is_signer = false },
            .{ .id = params.system_program.id, .is_writable = false, .is_signer = false },
            .{ .id = params.token_program.id, .is_writable = false, .is_signer = false },
            .{ .id = params.rent.id, .is_writable = false, .is_signer = false },
        },
        .data = data,
    });

    try instruction.invokeSigned(&.{
        params.funder,
        account,
        params.owner,
        params.mint,
        params.system_program,
        params.token_program,
        params.rent,
    }, params.seeds);
}

pub fn createIdempotentAccount(account: sol.Account.Info, params: struct {
    funder: sol.Account.Info,
    owner: sol.Account.Info,
    mint: sol.Account.Info,
    system_program: sol.Account.Info,
    token_program: sol.Account.Info,
    associated_token_program: sol.Account.Info,
    seeds: []const []const []const u8 = &.{},
}) !void {
    const data = try bincode.writeAlloc(sol.allocator, associated_token.Instruction.create_idempotent, .{});
    defer sol.allocator.free(data);

    const instruction = sol.Instruction.from(.{
        .program_id = &spl.associated_token_program_id,
        .accounts = &[_]sol.Account.Param{
            .{ .id = params.funder.id, .is_writable = true, .is_signer = true },
            .{ .id = account.id, .is_writable = true, .is_signer = false },
            .{ .id = params.owner.id, .is_writable = false, .is_signer = false },
            .{ .id = params.mint.id, .is_writable = false, .is_signer = false },
            .{ .id = params.system_program.id, .is_writable = false, .is_signer = false },
            .{ .id = params.token_program.id, .is_writable = false, .is_signer = false },
        },
        .data = data,
    });

    try instruction.invokeSigned(&.{
        params.funder,
        account,
        params.owner,
        params.mint,
        params.system_program,
        params.token_program,
        params.associated_token_program,
    }, params.seeds);
}

test {
    std.testing.refAllDecls(@This());
}
