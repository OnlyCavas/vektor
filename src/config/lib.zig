const std = @import("std");

pub const firewall = @import("firewall.zig");

pub const BootloaderConfig = @import("bootloader.zig").BootLoaderConfig;

pub const HardwareConfig = struct {
    cpu: enum {
        intel,
        amd,

        pub fn ucode(self: @This()) []const u8 {
            return switch (self) {
                .intel => "intel-ucode",
                .amd => "amd-ucode",
            };
        }
    },
    gpu: enum {
        intel,
        amd,
        nvidia,

        pub fn packages(self: @This()) []const []const u8 {
            return switch (self) {
                .intel => &.{ "mesa", "vulkan-intel", "intel-media-driver" },
                .amd => &.{ "mesa", "vulkan-radeon", "libva-mesa-driver" },
                .nvidia => &.{ "nvidia-dkms", "nvidia-utils", "dkms" },
            };
        }
    },
};

pub const PrivilegeEscalationConfig = enum {
    sudo,
    doas,
};

const SecurityConfig = struct {
    priviledgeEscalation: PrivilegeEscalationConfig = .sudo,
    firewall: firewall.Firewall = .default,
    bootloader: BootloaderConfig = .default,
};

pub const Shell = enum {
    zsh,
    bash,
    fish,

    pub fn getPackageName(self: Shell) []const u8 {
        return @tagName(self);
    }

    pub fn path(self: Shell) []const u8 {
        return switch (self) {
            .zsh => "/usr/bin/zsh",
            .bash => "/usr/bin/bash",
            .fish => "/usr/bin/fish",
        };
    }
};

const User = struct {
    name: []const u8,
    shell: Shell = .bash,
    groups: []const []const u8 = &.{ "wheel", "audio", "video" },
};

pub const SystemConfig = struct {
    hostname: []const u8,
    timezone: []const u8,
    locale: []const u8,
    keymap: []const u8,

    users: []const User,
};

pub const InitSystem = enum {
    dinit,
    runit,
    openrc,
    s6,

    pub fn suffix(self: InitSystem) []const u8 {
        return @tagName(self);
    }
};

pub const PackageSpec = struct {
    base: []const []const u8 = &.{},
    services: []const []const u8 = &.{},
    initSystem: InitSystem = .dinit,

    pub fn merge(comptime specs: []const PackageSpec) PackageSpec {
        comptime {
            var out: PackageSpec = .{};

            for (specs) |s| {
                out.base = out.base ++ s.base;
                out.services = out.services ++ s.services;
                out.initSystem = s.initSystem;
            }

            return out;
        }
    }

    fn dedup(comptime pkgs: []const []const u8) []const []const u8 {
        comptime var out: []const []const u8 = &[_][]const u8{};

        outer: inline for (pkgs) |p| {
            inline for (out) |q| {
                if (std.mem.eql(u8, p, q)) continue :outer;
            }

            out = out ++ &[_][]const u8{p};
        }

        return out;
    }

    pub fn packageList(comptime spec: PackageSpec) []const []const u8 {
        comptime {
            var out: []const []const u8 = spec.base ++ &[_][]const u8{spec.initSystem.suffix()};

            for (spec.services) |service| {
                out = out ++ &[_][]const u8{ service, service ++ "-" ++ spec.initSystem.suffix() };
            }

            return dedup(out);
        }
    }
};

pub const Partition = struct {
    label: []const u8,
    fs: enum { fat32, ext4, swap },
    size: union(enum) {
        mib: u64,
        gib: u64,
        remaining,
    },
    flags: []const enum { esp } = &.{},

    pub fn getFsName(part: Partition) []const u8 {
        return @tagName(part.fs);
    }
};

pub const Mount = struct {
    partition: []const u8,
    target: []const u8,
};

pub const DiskConfig = struct {
    device: []const u8,
    table: enum { gpt } = .gpt,
    partitions: []const Partition,
    mounts: []const Mount,

    pub fn getByLabel(disk: DiskConfig, label: []const u8) !usize {
        for (disk.partitions, 1..) |partition, index| {
            if (std.mem.eql(u8, partition.label, label)) return index;
        }

        return error.PartitionNotFound;
    }

    pub fn getRootIndex(disk: DiskConfig) !usize {
        for (disk.mounts) |mount| {
            if (std.mem.eql(u8, mount.target, "/"))
                return getByLabel(disk, mount.partition);
        }

        return error.NoRootMount;
    }

    pub fn getEFI(disk: DiskConfig) !usize {
        for (disk.partitions, 1..) |partition, index|
            for (partition.flags) |flag|
                if (flag == .esp) return index;

        return error.NoEFIPartition;
    }

    pub fn partDevice(disk: DiskConfig, allocator: std.mem.Allocator, idx: usize) ![]const u8 {
        const p = if (std.mem.indexOf(u8, disk.device, "nvme") != null or
            std.mem.indexOf(u8, disk.device, "mmcblk") != null) "p" else "";

        return std.fmt.allocPrint(allocator, "{s}{s}{d}", .{ disk.device, p, idx });
    }

    pub fn getTableName(disk: DiskConfig) []const u8 {
        return @tagName(disk.table);
    }
};

pub const InstallConfig = struct {
    disk: DiskConfig,
    system: SystemConfig,
    hardware: HardwareConfig,
    packages: PackageSpec = .{
        .base = &.{},
        .services = &.{},
        .initSystem = .runit,
    },
    security: SecurityConfig,
};
