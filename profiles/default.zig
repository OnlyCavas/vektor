const installer = @import("artix-installer").InstallConfig;

pub const Config = installer{
    .disk = .{
        .device = "/dev/vda",
        .table = .gpt,
        .partitions = &.{
            .{
                .label = "EFI",
                .fs = .fat32,
                .size = .{ .mib = 1024 },
                .flags = &.{.esp},
            },
            .{
                .label = "swap",
                .fs = .swap,
                .size = .{ .gib = 2 },
            },
            .{
                .label = "root",
                .fs = .ext4,
                .size = .{ .gib = 25 },
            },
            .{
                .label = "home",
                .fs = .ext4,
                .size = .remaining,
            },
        },
        .mounts = &.{
            .{ .partition = "root", .target = "/" },
            .{ .partition = "EFI", .target = "/boot" },
            .{ .partition = "home", .target = "/home" },
        },
    },
    .desktop = .{
        .desktopPortal = &.{
            .cosmic,
            .wlr,
        },
        .windowManager = .niri,
        .audio = .pipewire,
    },
    .system = .{
        .hostname = "citadel",
        .timezone = "Europe/Lisbon",
        .locale = "en_US.UTF-8",
        .keymap = "pt-latin1",
        .users = &.{
            .{
                .name = "cavas",
                .shell = .zsh,
                .groups = &.{ "wheel", "audio", "video" },
            },
        },
    },
    .hardware = .{ .cpu = .intel, .gpu = .virtual },
    .packages = .{
        .initSystem = .dinit,
        .base = &.{"alacritty"},
    },
    .repositories = .{
        .enable_arch = &.{ .extra, .multilib },
    },
    .security = .{
        .priviledgeEscalation = .doas,
        .firewall = .{
            .nftables = .{
                .lanCluster = &.{
                    .{
                        .label = "homelab",
                        .maskList = &.{"10.0.1.0/24"},
                    },
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
        },
        .bootloader = .{
            .limine = .{
                .withWindows = .{ .label = "Gaming Machine" },
                .timeout = 5,
                .bootEntryName = "Pandora Box",
                .entries = &.{
                    .{ .label = "LostRiver (Dual Soul)", .package = .standard },
                    .{ .label = "Citadel (Fort Nick)", .package = .hardened },
                },
            },
        },
    },
};
