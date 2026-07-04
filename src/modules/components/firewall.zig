const std = @import("std");
const config = @import("config");
const metafile = @import("metadata");

const PackageSpec = config.PackageSpec;
const InstallConfig = config.InstallConfig;

const FirewallConfig = config.firewall.Firewall;

const Ctx = @import("../lib.zig").Context;

pub const Firewall = struct {
    cfg: FirewallConfig,

    pub fn fromConfig(cfg: *const InstallConfig) Firewall {
        return .{ .cfg = cfg.security.firewall };
    }

    pub fn spec(self: Firewall) PackageSpec {
        return switch (self.cfg) {
            .none => .{},
            .nftables => .{
                .services = &.{"nftables"},
            },
        };
    }

    pub fn install(self: Firewall, ctx: *const Ctx) !void {
        const runner = ctx.runner;

        var arena: std.heap.ArenaAllocator = .init(runner.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        switch (self.cfg) {
            .none => {},
            .nftables => |nft| {
                const configFile = try metafile.makeNFTConfigFile(nft, allocator);
                try ctx.runner.writeFile("/mnt/etc/nftables.conf", configFile);
            },
        }
    }
};
