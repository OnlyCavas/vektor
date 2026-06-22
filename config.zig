const installer = @import("artix-installer").InstallConfig;

pub const Config = installer{
    .system = .{
        .hostname = "citadel",
        .timezone = "Europe/Lisbon",
        .locale = "en_US.UTF-8",
        .keymap = "pt-latin1",
        .users = &.{
            .{ .name = "cavas", .shell = "/bin/bash" },
        },
    },
    .security = .{
        .firewall = .disabled,
    },
};
