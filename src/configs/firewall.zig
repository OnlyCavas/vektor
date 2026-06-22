const NFTables = struct {
    default_policy: enum { drop, accept } = .drop,

    fn apply(fw: NFTables) !void {
        _ = fw;
    }
};

pub const Firewall = union(enum) {
    none: void,
    nftables: NFTables,

    pub const disabled: Firewall = .{ .none = {} };

    pub const default: Firewall = .{
        .nftables = .{
            .default_policy = .drop,
        },
    };

    pub fn apply(fw: Firewall) !void {
        switch (fw) {
            .nftables => |nftables| try nftables.apply(),
            .none => {},
        }
    }
};
