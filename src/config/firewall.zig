const NFTables = struct {
    default_policy: enum { drop, accept } = .drop,
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
};
