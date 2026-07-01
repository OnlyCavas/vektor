const config = @import("config");

const PackageSpec = config.PackageSpec;
const FirewallConfig = config.Firewall;

const Ctx = @import("../lib.zig").Context;

pub const Firewall = struct {
    cfg: FirewallConfig,

    pub fn init(cfg: FirewallConfig) Firewall {
        return .{ .cfg = cfg };
    }

    pub fn spec(self: Firewall) PackageSpec {
        return switch (self.cfg) {
            .none => .{},
            .nftables => .{ .base = &.{"nftables"}, .services = &.{"nftables"} },
        };
    }

    pub fn install(self: Firewall, ctx: *const Ctx) !void {
        switch (self.cfg) {
            .none => {},
            .nftables => {
                try ctx.runner.writeFile("/mnt/etc/nftables.conf", @embedFile("nftables.conf"));
                try ctx.services().enable("nftables");
            },
        }
    }
};
