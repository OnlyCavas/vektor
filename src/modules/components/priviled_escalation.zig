const config = @import("config");

const PackageSpec = config.PackageSpec;
const PrivelidgeEscalationConfig = config.PrivilegeEscalationConfig;
const InstallConfig = config.InstallConfig;

const Runner = @import("utils").Runner;
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

        try switch (cfg) {
            .doas => setupDoas(ctx.runner),
            .sudo => setupSudo(ctx.runner),
        };
    }

    fn setupDoas(runner: *Runner) !void {
        try runner.writeFile("/mnt/etc/doas.conf", doas_conf);
        try runner.execChroot(&.{ "chown", "-c", "root:root", "/etc/doas.conf" });
        try runner.execChroot(&.{ "chmod", "-c", "0400", "/etc/doas.conf" });

        try runner.execChroot(&.{ "pacman", "-Rdd", "--noconfirm", "sudo" });
        try runner.execChroot(&.{ "ln", "-sf", "/usr/bin/doas", "/usr/bin/sudo" });
    }

    fn setupSudo(runner: *Runner) !void {
        try runner.writeFile("/mnt/etc/sudoers.d/wheel", "%wheel ALL=(ALL:ALL) ALL\n");
        try runner.execChroot(&.{ "chmod", "0440", "/etc/sudoers.d/wheel" });
    }
};
