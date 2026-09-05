const std = @import("std");
const builtin = @import("builtin");

const emit = @import("emit.zig");
const ZigValue = @import("codegen.zig").ZigValue;

pub fn main(init: std.process.Init.Minimal) !void {
    const use_gpa = builtin.mode == .Debug;

    var gpa: std.heap.DebugAllocator(.{}) = .init;

    defer if (use_gpa) {
        _ = gpa.deinit();
    };

    const allocator = if (use_gpa)
        gpa.allocator()
    else
        std.heap.smp_allocator;

    const config: ZigValue = .{ .strct = &.{
        .{ .key = "disk", .value = .{ .strct = &.{
            .{ .key = "device", .value = .{ .string = "/dev/vda" } },
            .{ .key = "table", .value = .{ .enum_literal = "gpt" } },
            .{ .key = "partitions", .value = .{ .array = &.{
                .{ .strct = &.{
                    .{ .key = "label", .value = .{ .string = "EFI" } },
                    .{ .key = "fs", .value = .{ .enum_literal = "fat32" } },
                    .{ .key = "size", .value = .{ .strct = &.{
                        .{ .key = "mib", .value = .{ .integer = 1024 } },
                    } } },
                    .{ .key = "flags", .value = .{ .array = &.{
                        .{ .enum_literal = "esp" },
                    } } },
                } },
                .{ .strct = &.{
                    .{ .key = "label", .value = .{ .string = "swap" } },
                    .{ .key = "fs", .value = .{ .enum_literal = "swap" } },
                    .{ .key = "size", .value = .{ .strct = &.{
                        .{ .key = "gib", .value = .{ .integer = 2 } },
                    } } },
                } },
                .{ .strct = &.{
                    .{ .key = "label", .value = .{ .string = "root" } },
                    .{ .key = "fs", .value = .{ .enum_literal = "ext4" } },
                    .{ .key = "size", .value = .{ .strct = &.{
                        .{ .key = "gib", .value = .{ .integer = 25 } },
                    } } },
                } },
                .{ .strct = &.{
                    .{ .key = "label", .value = .{ .string = "home" } },
                    .{ .key = "fs", .value = .{ .enum_literal = "ext4" } },
                    .{ .key = "size", .value = .{ .enum_literal = "remaining" } },
                } },
            } } },
            .{ .key = "mounts", .value = .{ .array = &.{
                .{ .strct = &.{
                    .{ .key = "partition", .value = .{ .string = "root" } },
                    .{ .key = "target", .value = .{ .string = "/" } },
                } },
                .{ .strct = &.{
                    .{ .key = "partition", .value = .{ .string = "EFI" } },
                    .{ .key = "target", .value = .{ .string = "/boot" } },
                } },
                .{ .strct = &.{
                    .{ .key = "partition", .value = .{ .string = "home" } },
                    .{ .key = "target", .value = .{ .string = "/home" } },
                } },
            } } },
        } } },
        .{ .key = "desktop", .value = .{ .strct = &.{
            .{ .key = "desktopPortal", .value = .{ .array = &.{
                .{ .enum_literal = "cosmic" },
                .{ .enum_literal = "wlr" },
            } } },
            .{ .key = "windowManager", .value = .{ .enum_literal = "niri" } },
            .{ .key = "audio", .value = .{ .enum_literal = "pipewire" } },
        } } },
        .{ .key = "system", .value = .{ .strct = &.{
            .{ .key = "hostname", .value = .{ .string = "citadel" } },
            .{ .key = "timezone", .value = .{ .string = "Europe/Lisbon" } },
            .{ .key = "locale", .value = .{ .string = "en_US.UTF-8" } },
            .{ .key = "keymap", .value = .{ .string = "pt-latin1" } },
            .{ .key = "users", .value = .{ .array = &.{
                .{ .strct = &.{
                    .{ .key = "name", .value = .{ .string = "cavas" } },
                    .{ .key = "shell", .value = .{ .enum_literal = "zsh" } },
                    .{ .key = "groups", .value = .{ .array = &.{
                        .{ .string = "wheel" },
                        .{ .string = "audio" },
                        .{ .string = "video" },
                    } } },
                } },
            } } },
        } } },
        .{ .key = "hardware", .value = .{ .strct = &.{
            .{ .key = "cpu", .value = .{ .enum_literal = "intel" } },
            .{ .key = "gpu", .value = .{ .enum_literal = "virtual" } },
        } } },
        .{ .key = "packages", .value = .{ .strct = &.{
            .{ .key = "initSystem", .value = .{ .enum_literal = "dinit" } },
            .{ .key = "base", .value = .{ .array = &.{
                .{ .string = "alacritty" },
            } } },
        } } },
        .{ .key = "repositories", .value = .{ .strct = &.{
            .{ .key = "enable_arch", .value = .{ .array = &.{
                .{ .enum_literal = "extra" },
                .{ .enum_literal = "multilib" },
            } } },
        } } },
        .{ .key = "security", .value = .{ .strct = &.{
            .{ .key = "priviledgeEscalation", .value = .{ .enum_literal = "doas" } },
            .{ .key = "firewall", .value = .{ .strct = &.{
                .{ .key = "nftables", .value = .{ .strct = &.{
                    .{ .key = "lanCluster", .value = .{ .array = &.{
                        .{ .strct = &.{
                            .{ .key = "label", .value = .{ .string = "homelab" } },
                            .{ .key = "maskList", .value = .{ .array = &.{
                                .{ .string = "10.0.1.0/24" },
                            } } },
                        } },
                    } } },
                    .{ .key = "input", .value = .{ .strct = &.{
                        .{ .key = "policy", .value = .{ .enum_literal = "drop" } },
                        .{ .key = "rules", .value = .{ .array = &.{
                            .{ .strct = &.{
                                .{ .key = "clusterLabel", .value = .{ .string = "homelab" } },
                                .{ .key = "extend", .value = .{ .string = "icmp type echo-request" } },
                                .{ .key = "policy", .value = .{ .enum_literal = "accept" } },
                            } },
                            .{ .strct = &.{
                                .{ .key = "clusterLabel", .value = .{ .string = "homelab" } },
                                .{ .key = "protocol", .value = .{ .enum_literal = "tcp" } },
                                .{ .key = "dport", .value = .{ .string = "22" } },
                                .{ .key = "extend", .value = .{ .string = "ct state new limit rate 5/minute" } },
                                .{ .key = "policy", .value = .{ .enum_literal = "accept" } },
                            } },
                        } } },
                    } } },
                } } },
            } } },
            .{ .key = "bootloader", .value = .{ .strct = &.{
                .{ .key = "limine", .value = .{ .strct = &.{
                    .{ .key = "withWindows", .value = .{ .strct = &.{
                        .{ .key = "label", .value = .{ .string = "Gaming Machine" } },
                    } } },
                    .{ .key = "timeout", .value = .{ .integer = 5 } },
                    .{ .key = "bootEntryName", .value = .{ .string = "Pandora Box" } },
                    .{ .key = "entries", .value = .{ .array = &.{
                        .{ .strct = &.{
                            .{ .key = "label", .value = .{ .string = "LostRiver (Dual Soul)" } },
                            .{ .key = "package", .value = .{ .enum_literal = "standard" } },
                        } },
                        .{ .strct = &.{
                            .{ .key = "label", .value = .{ .string = "Citadel (Fort Nick)" } },
                            .{ .key = "package", .value = .{ .enum_literal = "hardened" } },
                        } },
                    } } },
                } } },
            } } },
        } } },
    } };

    var threaded: std.Io.Threaded = .init(allocator, .{ .environ = init.environ });
    defer threaded.deinit();

    try emit.writeProfile(allocator, threaded.io(), config, "./src/core/profile.zig");
}
