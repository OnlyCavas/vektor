const LanCluster = struct {
    label: []const u8,
    maskList: []const []const u8,
};

const Policy = enum {
    accept,
    drop,
    reject,

    pub fn getName(self: Policy) []const u8 {
        return @tagName(self);
    }
};

const Protocol = enum {
    tcp,
    udp,

    pub fn getName(self: Protocol) []const u8 {
        return @tagName(self);
    }
};

const Rules = struct {
    clusterLabel: ?[]const u8 = null,
    protocol: ?enum { tcp, udp } = null,
    dport: ?[]const u8 = null,
    sport: ?[]const u8 = null,
    extend: ?[]const u8 = null,
    policy: Policy = .drop,
};

const Chain = struct {
    rules: []const Rules = &.{},
    policy: Policy,
};

pub const NFTables = struct {
    lanCluster: []const LanCluster = &.{},

    input: Chain = .{ .policy = .drop },
    forward: Chain = .{ .policy = .drop },
    output: Chain = .{ .policy = .drop },
};

pub const Firewall = union(enum) {
    none: void,
    nftables: NFTables,

    pub const disabled: Firewall = .{ .none = {} };

    pub const default: Firewall = .{
        .nftables = .{
            .lanCluster = &.{
                .{ .label = "homelab", .maskList = &.{"10.0.1.0/24"} },
            },
            .input = .{
                .policy = .drop,
                .rules = &.{
                    .{
                        .clusterLabel = "homelab",
                        .extend = "icmp type echo-request",
                        .policy = .accept,
                    },
                    .{
                        .clusterLabel = "homelab",
                        .protocol = .tcp,
                        .dport = "22",
                        .extend = "ct state new limit rate 5/minute",
                        .policy = .accept,
                    },
                },
            },
        },
    };
};
