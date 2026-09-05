const std = @import("std");
const config_types = @import("config_types");

const metafile = @import("../metadata/lib.zig");

const PackageSpec = config_types.PackageSpec;
const InstallConfig = config_types.InstallConfig;
const FirewallConfig = config_types.Firewall;

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
                .services = &.{
                    .{ .pkg = "nftables" },
                },
            },
        };
    }

    pub fn install(self: Firewall, ctx: *const Ctx) !void {
        var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        switch (self.cfg) {
            .none => {},
            .nftables => |nft| {
                const configFile = try metafile.makeNFTConfigFile(nft, allocator);
                try ctx.runner.writeFile(allocator, "/mnt/etc/nftables.conf", configFile);
            },
        }
    }
};
