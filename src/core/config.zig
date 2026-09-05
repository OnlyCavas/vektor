const std = @import("std");

const LanCluster = struct {
    label: []const u8,
    maskList: []const []const u8,
};

const Policy = enum {
    accept,
    drop,
    reject,

    pub fn getName(self: Policy) []const u8 {
        return @tagName(self);
    }
};

const Protocol = enum {
    tcp,
    udp,

    pub fn getName(self: Protocol) []const u8 {
        return @tagName(self);
    }
};

const Rules = struct {
    clusterLabel: ?[]const u8 = null,
    protocol: ?enum { tcp, udp } = null,
    dport: ?[]const u8 = null,
    sport: ?[]const u8 = null,
    extend: ?[]const u8 = null,
    policy: Policy = .drop,
};

const Chain = struct {
    rules: []const Rules = &.{},
    policy: Policy,
};

pub const NFTables = struct {
    lanCluster: []const LanCluster = &.{},

    input: Chain = .{ .policy = .drop },
    forward: Chain = .{ .policy = .drop },
    output: Chain = .{ .policy = .drop },
};

pub const Firewall = union(enum) {
    none: void,
    nftables: NFTables,

    pub const disabled: Firewall = .{ .none = {} };

    pub const default: Firewall = .{
        .nftables = .{
            .lanCluster = &.{
                .{ .label = "homelab", .maskList = &.{"10.0.1.0/24"} },
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
    };
};

pub const KernelEntry = struct {
    label: []const u8,
    package: enum {
        standard,
        lts,
        hardened,

        pub fn name(self: @This()) []const u8 {
            return switch (self) {
                .standard => "linux",
                .lts => "linux-lts",
                .hardened => "linux-hardened",
            };
        }

        pub fn packages(self: @This()) []const []const u8 {
            return switch (self) {
                .standard => &.{ "linux", "linux-headers" },
                .lts => &.{ "linux-lts", "linux-lts-headers" },
                .hardened => &.{ "linux-hardened", "linux-hardened-headers" },
            };
        }
    },
};

pub const LimineConfig = struct {
    timeout: u32 = 5,
    withWindows: ?struct { label: []const u8 } = null,
    bootEntryName: []const u8 = "Artix Limine",
    entries: []const KernelEntry = &.{
        .{
            .label = "Artix Linux",
            .package = .standard,
        },
    },

    pub const default: LimineConfig = .{};
};

pub const BootLoaderConfig = union(enum) {
    limine: LimineConfig,

    pub const default: BootLoaderConfig = .{ .limine = .default };
};

pub const HardwareConfig = struct {
    cpu: enum {
        intel,
        amd,
    },
    gpu: enum {
        intel,
        amd,
        nvidia,
        virtual,
    },
};

pub const DotfilesConfig = struct {
    git: []const u8,
    commit: ?[]const u8,
    entryPoint: union(enum) {
        script: []const u8,
        fnl,
    },
};

pub const PrivilegeEscalationConfig = enum {
    sudo,
    doas,
};

const SecurityConfig = struct {
    priviledgeEscalation: PrivilegeEscalationConfig = .sudo,
    firewall: Firewall = .default,
    bootloader: BootLoaderConfig = .default,
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

    pub fn primaryUser(self: SystemConfig) !User {
        if (self.users.len == 0) return error.NoUsers;

        return self.users[0];
    }
};

pub const InitSystem = enum {
    dinit,
    runit,
    openrc,
    s6,

    pub fn enable(self: InitSystem, service: []const u8, allocator: std.mem.Allocator) !void {
        const dir = switch (self) {
            .dinit => "/etc/dinit.d/{s}",
            .runit => "/etc/runit/sv/{s}",
            .s6 => "/etc/s6/adminsv/default/contents.d/{s}",
        };

        const target = try std.fmt.allocPrint(allocator, dir, .{service});
        defer allocator.free(target);

        return switch (self) {
            .runit => &.{ "ln", "-sf", target, "/etc/runit/runsvdir/default/" },
            .dinit => &.{ "ln", "-sf", target, "/etc/dinit.d/boot.d/" },
            .s6 => &.{ "touch", target },
        };
    }

    pub fn suffix(self: InitSystem) []const u8 {
        return @tagName(self);
    }
};

pub const ServiceSpec = struct {
    pkg: []const u8,
    name: ?[]const u8 = null,
    scope: enum { boot, user } = .boot,

    pub fn service(self: ServiceSpec) []const u8 {
        return self.name orelse self.pkg;
    }
};

pub const PackageSpec = struct {
    base: []const []const u8 = &.{},
    services: []const ServiceSpec = &.{},
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
        @setEvalBranchQuota(10_000);

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
                out = out ++ &[_][]const u8{
                    service.pkg,
                    service.pkg ++ "-" ++ spec.initSystem.suffix(),
                };
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

    pub fn getEFIndex(disk: DiskConfig) !usize {
        for (disk.partitions, 1..) |partition, index|
            for (partition.flags) |flag|
                if (flag == .esp) return index;

        return error.NoEFIPartition;
    }

    pub fn getSwapIndex(disk: DiskConfig) !usize {
        for (disk.partitions, 1..) |partition, index|
            if (partition.fs == .swap) return index;

        return error.NoSwapPartition;
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

pub const ArchRepositories = enum {
    extra,
    multilib,

    pub fn getName(self: ArchRepositories) []const u8 {
        return @tagName(self);
    }
};

pub const RepositoryConfig = struct {
    enable_arch: ?[]const ArchRepositories = null,
};

pub const WindowManagerConfig = enum {
    niri,
    hyprland,

    pub fn getName(self: WindowManagerConfig) []const u8 {
        return @tagName(self);
    }
};

pub const DesktopPortalConfig = enum {
    cosmic,
    wlr,
    hyprland,
    gnome,
    gtk,
};

pub const AudioBackendConfig = enum {
    pipewire,
    pulseaudio,
    none,
};

pub const DesktopConfig = struct {
    windowManager: WindowManagerConfig = .niri,
    desktopPortal: []const DesktopPortalConfig = &.{},
    audio: AudioBackendConfig = .pipewire,
};

pub const InstallConfig = struct {
    desktop: DesktopConfig,
    disk: DiskConfig,
    system: SystemConfig,
    hardware: HardwareConfig,
    packages: PackageSpec = .{
        .base = &.{},
        .services = &.{},
        .initSystem = .runit,
    },
    repositories: RepositoryConfig,
    security: SecurityConfig,
};
