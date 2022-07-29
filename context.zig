const std = @import("std");
const sol = @import("sol.zig");

pub const Context = struct {
    num_accounts: usize,
    accounts: [*]u8,
    data: []const u8,
    program_id: *sol.PublicKey,

    pub fn load(input: [*]u8) !Context {
        var ptr: [*]u8 = input;

        const num_accounts = std.mem.bytesToValue(usize, ptr[0..@sizeOf(usize)]);
        ptr += @sizeOf(usize);

        const accounts: [*]u8 = ptr;

        var i: usize = 0;
        while (i < num_accounts) : (i += 1) {
            const account: *align(1) sol.Account.Data = @ptrCast(*align(1) sol.Account.Data, ptr);
            if (account.duplicate_index != std.math.maxInt(u8)) {
                ptr += @sizeOf(usize);
                continue;
            }
            ptr += @sizeOf(sol.Account.Data);
            ptr = @intToPtr([*]u8, std.mem.alignForward(@ptrToInt(ptr + account.data_len + 10 * 1024), @alignOf(usize)));
            ptr += @sizeOf(u64);
        }

        const data_len = std.mem.bytesToValue(u64, ptr[0..@sizeOf(u64)]);
        ptr += @sizeOf(u64);

        const data = ptr[0..data_len];
        ptr += data_len;

        const program_id = @ptrCast(*sol.PublicKey, ptr);
        ptr += @sizeOf(sol.PublicKey);

        return Context{
            .num_accounts = num_accounts,
            .accounts = accounts,
            .data = data,
            .program_id = program_id,
        };
    }

    pub fn loadAccountsAlloc(self: Context, comptime Accounts: type, gpa: std.mem.Allocator) !*Accounts {
        const accounts = try gpa.create(Accounts);
        errdefer gpa.destroy(accounts);

        try self.populateAccounts(Accounts, accounts);

        return accounts;
    }

    pub fn loadAccounts(self: Context, comptime Accounts: type) !Accounts {
        var accounts: Accounts = undefined;
        try self.populateAccounts(Accounts, &accounts);
        return accounts;
    }

    fn populateAccounts(self: Context, comptime Accounts: type, accounts: *Accounts) !void {
        comptime var min_accounts = 0;
        comptime var last_field_is_slice = false;

        comptime {
            inline for (@typeInfo(Accounts).Struct.fields) |field, i| {
                switch (field.field_type) {
                    sol.Account => min_accounts += 1,
                    []sol.Account => {
                        if (i != @typeInfo(Accounts).Struct.fields.len - 1) {
                            @compileError("Only the last field of an 'Accounts' struct may be a slice of accounts.");
                        }
                        last_field_is_slice = true;
                    },
                    else => @compileError(""),
                }
            }
        }

        if (self.num_accounts < min_accounts) {
            return error.NotEnoughAccounts;
        }

        var ptr: [*]u8 = self.accounts;

        inline for (@typeInfo(Accounts).Struct.fields) |field| {
            const account: *align(1) sol.Account.Data = @ptrCast(*align(1) sol.Account.Data, ptr);
            if (account.duplicate_index != std.math.maxInt(u8)) {
                inline for (@typeInfo(Accounts).Struct.fields) |cloned_field, cloned_index| {
                    if (account.duplicate_index == cloned_index) {
                        @field(accounts, field.name) = @field(accounts, cloned_field.name);
                    }
                }
                ptr += @sizeOf(usize);
            } else {
                const start = @ptrToInt(ptr);
                ptr += @sizeOf(sol.Account.Data);
                ptr = @intToPtr([*]u8, std.mem.alignForward(@ptrToInt(ptr + account.data_len + 10 * 1024), @alignOf(usize)));
                ptr += @sizeOf(u64);
                const end = @ptrToInt(ptr);

                switch (field.field_type) {
                    sol.Account => @field(accounts, field.name) = .{ .ptr = @alignCast(@alignOf(sol.Account.Data), account), .len = end - start },
                    else => @compileError(""),
                }
            }
        }
    }
};
