const std = @import("std");
const config = @import("config");

const LimineConfigFile = @import("metadata").LimineConfigFile;

const InstallConfig = config.InstallConfig;
const DiskConfig = config.DiskConfig;
const BootloaderConfig = config.BootloaderConfig;
const PackageSpec = config.PackageSpec;

const Ctx = @import("../lib.zig").Context;
const Runner = @import("utils").Runner;

pub const Bootloader = struct {
    cfg: BootloaderConfig,

    pub fn fromConfig(cfg: *const InstallConfig) Bootloader {
        return .{ .cfg = cfg.security.bootloader };
    }

    pub fn spec(self: Bootloader) PackageSpec {
        switch (self.cfg) {
            .limine => |lc| {
                comptime var base: []const []const u8 = &.{ "limine", "efibootmgr", "dracut", "gummiboot" };

                inline for (lc.entries) |e|
                    base = base ++ &[_][]const u8{e.package.name()};

                return .{ .base = base };
            },
        }
    }

    pub fn install(self: Bootloader, ctx: *const Ctx) !void {
        const runner = ctx.runner;
        const cfg = ctx.cfg;

        var arena: std.heap.ArenaAllocator = .init(runner.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        try runner.exec(&.{ "mount", "--bind", "/proc", "/mnt/proc" });
        try runner.exec(&.{ "mount", "--bind", "/sys", "/mnt/sys" });
        try runner.exec(&.{ "mount", "--bind", "/dev", "/mnt/dev" });

        const kernelImages = try createUFIimages(runner, allocator, cfg.disk);

        switch (self.cfg) {
            .limine => {
                const limineConfig = self.cfg.limine;

                try runner.exec(&.{ "mkdir", "-p", "/mnt/boot/limine" });

                try self.writeConfigFile(runner, allocator, kernelImages);

                try runner.exec(&.{
                    "cp",
                    "/mnt/usr/share/limine/BOOTX64.EFI",
                    "/mnt/boot/limine/BOOTX64.EFI",
                });

                const partition = try std.fmt.allocPrint(allocator, "{d}", .{try ctx.cfg.disk.getEFI()});
                defer allocator.free(partition);

                try runner.exec(&.{
                    "efibootmgr", "--create",
                    "--disk",     cfg.disk.device,
                    "--part",     partition,
                    "--label",    limineConfig.bootEntryName,
                    "--loader",   "/limine/BOOTX64.EFI",
                });
            },
        }
    }

    fn contains(haystack: []const []const u8, needle: []const u8) bool {
        for (haystack) |h|
            if (std.mem.eql(u8, h, needle)) return true;

        return false;
    }

    fn writeConfigFile(
        self: Bootloader,
        runner: *Runner,
        allocator: std.mem.Allocator,
        kernels: []const []const u8,
    ) !void {
        switch (self.cfg) {
            .limine => |lc| {
                var conf: std.ArrayList(u8) = .empty;
                defer conf.deinit(allocator);

                try conf.appendSlice(allocator, try std.fmt.allocPrint(allocator, "timeout: {d}\n\n", .{lc.timeout}));

                for (lc.entries) |entry| {
                    const pkg = entry.package.name();

                    if (!contains(kernels, pkg)) continue;

                    try conf.appendSlice(allocator, try std.fmt.allocPrint(
                        allocator,
                        "/{s}\n    protocol: efi_chainload\n    path: boot():/EFI/Linux/{s}.efi\n\n",
                        .{ entry.label, pkg },
                    ));
                }

                if (lc.withWindows) |entry|
                    try conf.appendSlice(allocator, try std.fmt.allocPrint(
                        allocator,
                        "/{s}\n    protocol: efi_chainload\n    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n\n",
                        .{entry.label},
                    ));

                try runner.writeFile("/mnt/boot/limine/limine.conf", conf.items);
            },
        }
    }

    fn createUFIimages(runner: *Runner, allocator: std.mem.Allocator, disk: DiskConfig) ![]const []const u8 {
        try runner.exec(&.{ "mkdir", "-p", "/mnt/boot/EFI/Linux" });

        const rootPartition = try disk.partDevice(allocator, try disk.getRootIndex());
        defer allocator.free(rootPartition);

        const uuid_raw = try runner.execRead(allocator, &.{ "blkid", "-s", "UUID", "-o", "value", rootPartition });
        defer allocator.free(uuid_raw);

        const uuid = std.mem.trim(u8, uuid_raw, " \n\r");

        const cmdline = try std.fmt.allocPrint(allocator, "root=UUID={s} rw", .{uuid});
        defer allocator.free(cmdline);

        try runner.writeFile("/mnt/etc/kernel/cmdline", cmdline);

        const listKernels = try runner.execRead(allocator, &.{ "ls", "/mnt/lib/modules" });
        defer allocator.free(listKernels);

        var names: std.ArrayList([]const u8) = .empty;
        var token = std.mem.tokenizeAny(u8, listKernels, " \n\r");

        while (token.next()) |kernel| {
            const pkgbasePath = try std.fmt.allocPrint(allocator, "/mnt/lib/modules/{s}/pkgbase", .{kernel});
            defer allocator.free(pkgbasePath);

            const pkgbaseRaw = runner.execRead(allocator, &.{ "cat", pkgbasePath }) catch continue;
            defer allocator.free(pkgbaseRaw);

            const kernelName = std.mem.trim(u8, pkgbaseRaw, " \n\r");
            const efiX64 = try std.fmt.allocPrint(allocator, "/boot/EFI/Linux/{s}.efi", .{kernelName});
            defer allocator.free(efiX64);

            try runner.execChroot(&.{
                "dracut",
                "--force",
                "--uefi",
                "--no-hostonly",
                "--uefi",
                "--add-drivers",
                "virtio_blk virtio_pci nvme ahci ext4 btrfs",
                "--kernel-cmdline",
                cmdline,
                "--kver",
                kernel,
                efiX64,
            });

            try names.append(allocator, try allocator.dupe(u8, kernelName));
        }

        return names.items;
    }
};
