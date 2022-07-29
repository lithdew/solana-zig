const sol = @import("sol.zig");

const bpf = @This();

pub const UpgradeableLoaderState = union(enum(u32)) {
    pub const ProgramData = struct {
        slot: u64,
        upgrade_authority_id: ?sol.PublicKey,
    };

    uninitialized: void,
    buffer: struct {
        authority_id: ?sol.PublicKey,
    },
    program: struct {
        program_data_id: sol.PublicKey,
    },
    program_data: ProgramData,
};

pub fn getUpgradeableLoaderProgramDataId(program_id: sol.PublicKey) !sol.PublicKey {
    const pda = try sol.PublicKey.findProgramAddress(.{program_id}, sol.bpf_upgradeable_loader_program_id);
    return pda.address;
}
