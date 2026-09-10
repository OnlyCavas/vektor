const std = @import("std");
const config_types = @import("config_types");

const PackageSpec = config_types.PackageSpec;
const InstallConfig = config_types.InstallConfig;
const RepositoryConfig = config_types.RepositoryConfig;

const Ctx = @import("../context.zig").Context;

pub const Repositories = struct {
    cfg: RepositoryConfig,

    pub fn fromConfig(cfg: *const InstallConfig) Repositories {
        return .{ .cfg = cfg.repositories };
    }

    pub fn spec(self: Repositories) PackageSpec {
        var packages: []const []const u8 = &.{};

        if (self.cfg.enable_arch != null)
            packages = packages ++ .{"artix-archlinux-support"};

        return .{ .base = packages };
    }

    pub fn install(self: Repositories, ctx: *const Ctx) !void {
        const runner = ctx.runner;

        var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        try runner.exec(allocator, &.{ "sed", "-i", "s/^#Color/Color/", "/mnt/etc/pacman.conf" });
        try runner.exec(allocator, &.{ "sed", "-i", "/^Color/a ILoveCandy", "/mnt/etc/pacman.conf" });

        if (self.cfg.enable_arch) |repos| {
            var allocWriter: std.Io.Writer.Allocating = .init(allocator);
            defer allocWriter.deinit();
            const writer = &allocWriter.writer;

            for (repos) |r| {
                try writer.print(
                    \\[{s}]
                    \\Include = /etc/pacman.d/mirrorlist-arch
                    \\
                    \\
                , .{r.getName()});
            }

            const append = try allocWriter.toOwnedSlice();
            defer allocator.free(append);

            try runner.appendToFile(allocator, "/mnt/etc/pacman.conf", append);
        }
    }
};
