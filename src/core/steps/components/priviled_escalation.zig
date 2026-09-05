const std = @import("std");
const config_types = @import("config_types");

const Allocator = std.mem.Allocator;

const PackageSpec = config_types.PackageSpec;
const PrivelidgeEscalationConfig = config_types.PrivilegeEscalationConfig;
const InstallConfig = config_types.InstallConfig;

const Runner = @import("cwd").Runner;
const Ctx = @import("../lib.zig").Context;

const doas_conf = "permit persist setenv { PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin } :wheel\n";
const sudoers_wheel = "%wheel ALL=(ALL:ALL) ALL\n";

pub const PrivelidgeEscalation = struct {
    cfg: PrivelidgeEscalationConfig,

    pub fn fromConfig(cfg: *const InstallConfig) PrivelidgeEscalation {
        return .{ .cfg = cfg.security.priviledgeEscalation };
    }

    pub fn spec(self: PrivelidgeEscalation) PackageSpec {
        return switch (self.cfg) {
            .doas => .{ .base = &.{"opendoas"} },
            .sudo => .{},
        };
    }

    pub fn install(self: PrivelidgeEscalation, ctx: *const Ctx) !void {
        const cfg = self.cfg;

        var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        try switch (cfg) {
            .doas => setupDoas(ctx.runner, allocator),
            .sudo => setupSudo(ctx.runner, allocator),
        };
    }

    fn setupDoas(runner: *Runner, allocator: Allocator) !void {
        try runner.writeFile(allocator, "/mnt/etc/doas.conf", doas_conf);
        try runner.execChroot(allocator, &.{ "chown", "-c", "root:root", "/etc/doas.conf" });
        try runner.execChroot(allocator, &.{ "chmod", "-c", "0400", "/etc/doas.conf" });

        try runner.execChroot(allocator, &.{ "pacman", "-Rdd", "--noconfirm", "sudo" });
        try runner.execChroot(allocator, &.{ "ln", "-sf", "/usr/bin/doas", "/usr/bin/sudo" });
    }

    fn setupSudo(runner: *Runner, allocator: Allocator) !void {
        try runner.writeFile(allocator, "/mnt/etc/sudoers.d/wheel", "%wheel ALL=(ALL:ALL) ALL\n");
        try runner.execChroot(allocator, &.{ "chmod", "0440", "/etc/sudoers.d/wheel" });
    }
};
