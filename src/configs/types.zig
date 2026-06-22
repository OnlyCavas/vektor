const std = @import("std");

const Firewall = @import("firewall.zig").Firewall;

const SecurityConfig = struct {
    firewall: Firewall = .default,
};

const User = struct {
    name: []const u8,
    shell: []const u8 = "/bin/zsh",
    groups: []const []const u8 = &.{ "wheel", "audio", "video" },
};

const SystemConfig = struct {
    hostname: []const u8,
    timezone: []const u8,
    locale: []const u8,
    keymap: []const u8,

    users: []const User,
};

pub const InstallConfig = struct {
    dry_run: bool = false,
    system: SystemConfig,
    packages: []const []const u8 = &.{"base"},
    security: SecurityConfig,
};
