const std = @import("std");
const config = @import("config");
const bootloaderConfig = @import("config").bootloader;

const InstallConfig = config.InstallConfig;
const DiskConfig = config.DiskConfig;
const PackageSpec = config.PackageSpec;

const BootloaderConfig = bootloaderConfig.BootLoaderConfig;
const LimineConfig = bootloaderConfig.LimineConfig;
const LimineConfigFile = @import("metadata").LimineConfigFile;

const Ctx = @import("../lib.zig").Context;
const Runner = @import("utils").Runner;

const UnifiedKernelImage = struct {
    kernelLabel: []const u8,
    blake2Hash: []const u8,
};

pub const Bootloader = struct {
    cfg: BootloaderConfig,

    pub fn fromConfig(cfg: *const InstallConfig) Bootloader {
        return .{ .cfg = cfg.security.bootloader };
    }

    pub fn spec(self: Bootloader) PackageSpec {
        comptime var base: []const []const u8 = &.{
            "efibootmgr",
            "dracut",
            "gummiboot",
        };

        switch (self.cfg) {
            .limine => |lc| {
                inline for (lc.entries) |e|
                    base = base ++ e.package.packages();

                return .{ .base = base ++ [_][]const u8{"limine"} };
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

        const kernelImages = try createUFIimages(runner, allocator, cfg.*);

        try switch (self.cfg) {
            .limine => |lc| self.setupLimine(
                ctx,
                allocator,
                kernelImages,
                lc,
            ),
        };
    }

    fn setupLimine(
        self: Bootloader,
        ctx: *const Ctx,
        allocator: std.mem.Allocator,
        kernelImages: []const UnifiedKernelImage,
        lc: LimineConfig,
    ) !void {
        const runner = ctx.runner;

        try runner.exec(&.{ "mkdir", "-p", "/mnt/boot/limine" });
        try self.writeConfigFile(runner, allocator, kernelImages);

        try runner.exec(&.{
            "cp",
            "/mnt/usr/share/limine/BOOTX64.EFI",
            "/mnt/boot/limine/BOOTX64.EFI",
        });

        const partition = try std.fmt.allocPrint(allocator, "{d}", .{try ctx.cfg.disk.getEFIndex()});
        defer allocator.free(partition);

        const nramOutput = try runner.execRead(allocator, &.{
            "sh",
            "-c",
            "efibootmgr -v | grep -B1 'Pandora Box' | grep -oP '^Boot\\K[0-9A-F]{4}'",
        });
        defer allocator.free(nramOutput);

        const nvramEntry = std.mem.trim(u8, nramOutput, " \t\r\n");

        if (nvramEntry.len != 0) {
            var entryIter = std.mem.tokenizeAny(u8, nvramEntry, " \t\r\n");

            while (entryIter.next()) |entry| {
                std.debug.print("deleting {s} entry", .{entry});

                try runner.exec(&.{
                    "efibootmgr", "-b", entry, "-B",
                });
            }
        }

        try runner.exec(&.{
            "efibootmgr", "--create",
            "--disk",     ctx.cfg.disk.device,
            "--part",     partition,
            "--label",    lc.bootEntryName,
            "--loader",   "/limine/BOOTX64.EFI",
        });

        const limineConfigHash = try b2sum(
            "/boot/limine/limine.conf",
            runner,
            allocator,
        );

        try runner.execChroot(&.{
            "limine",
            "enroll-config",
            "/boot/limine/BOOTX64.EFI",
            limineConfigHash,
        });
    }

    fn getKernel(haystack: []const UnifiedKernelImage, needle: []const u8) ?UnifiedKernelImage {
        for (haystack) |h|
            if (std.mem.eql(u8, h.kernelLabel, needle)) return h;

        return null;
    }

    fn writeConfigFile(
        self: Bootloader,
        runner: *Runner,
        allocator: std.mem.Allocator,
        kernels: []const UnifiedKernelImage,
    ) !void {
        switch (self.cfg) {
            .limine => |lc| {
                var conf: std.ArrayList(u8) = .empty;
                defer conf.deinit(allocator);

                try conf.appendSlice(allocator, try std.fmt.allocPrint(allocator, "timeout: {d}\n\n", .{lc.timeout}));

                for (lc.entries) |entry| {
                    const pkg = entry.package.name();
                    const kernel = getKernel(kernels, pkg) orelse continue;

                    try conf.appendSlice(allocator, try std.fmt.allocPrint(
                        allocator,
                        "/{s}\n    protocol: efi_chainload\n    path: boot():/EFI/Linux/{s}.efi#{s}\n\n",
                        .{
                            entry.label,
                            kernel.kernelLabel,
                            kernel.blake2Hash,
                        },
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

    fn createUFIimages(runner: *Runner, allocator: std.mem.Allocator, cfg: InstallConfig) ![]const UnifiedKernelImage {
        try runner.exec(&.{ "mkdir", "-p", "/mnt/boot/EFI/Linux" });

        const rootPartition = try cfg.disk.partDevice(allocator, try cfg.disk.getRootIndex());
        defer allocator.free(rootPartition);

        const uuid_raw = try runner.execRead(allocator, &.{ "blkid", "-s", "UUID", "-o", "value", rootPartition });
        defer allocator.free(uuid_raw);

        const uuid = std.mem.trim(u8, uuid_raw, " \n\r");

        const cmdline = try std.fmt.allocPrint(allocator, "root=UUID={s} rw quiet splash", .{uuid});
        defer allocator.free(cmdline);

        try runner.writeFile("/mnt/etc/kernel/cmdline", cmdline);

        const listKernels = try runner.execRead(allocator, &.{ "ls", "/mnt/lib/modules" });
        defer allocator.free(listKernels);

        var images: std.ArrayList(UnifiedKernelImage) = .empty;
        var token = std.mem.tokenizeAny(u8, listKernels, " \n\r");

        while (token.next()) |kernel| {
            const pkgbasePath = try std.fmt.allocPrint(allocator, "/mnt/lib/modules/{s}/pkgbase", .{kernel});
            defer allocator.free(pkgbasePath);

            const pkgbaseRaw = runner.execRead(allocator, &.{ "cat", pkgbasePath }) catch continue;
            defer allocator.free(pkgbaseRaw);

            const kernelName = std.mem.trim(u8, pkgbaseRaw, " \n\r");
            const efiX64 = try std.fmt.allocPrint(allocator, "/boot/EFI/Linux/{s}.efi", .{kernelName});
            defer allocator.free(efiX64);

            const drivers: []const []const u8 = if (cfg.hardware.gpu == .virtual)
                &[_][]const u8{ "nvme", "ahci", "ext4", "btrfs", "virtio_blk", "virtio_pci" }
            else
                &[_][]const u8{ "nvme", "ahci", "ext4", "btrfs" };

            const serializedDrivers = try std.mem.join(allocator, " ", drivers);
            defer allocator.free(serializedDrivers);

            try runner.execChroot(&.{
                "dracut",
                "--force",
                "--uefi",
                "--add-drivers",
                serializedDrivers,
                "--kernel-cmdline",
                cmdline,
                "--kver",
                kernel,
                efiX64,
            });

            try images.append(allocator, .{
                .kernelLabel = try allocator.dupe(u8, kernelName),
                .blake2Hash = try b2sum(efiX64, runner, allocator),
            });
        }

        return images.items;
    }

    fn b2sum(ufiPath: []const u8, runner: *Runner, allocator: std.mem.Allocator) ![]const u8 {
        const hostEfiPath = try std.fmt.allocPrint(allocator, "/mnt{s}", .{ufiPath});
        defer allocator.free(hostEfiPath);

        if (runner.options.dry_run) return "b2sum_hash";

        const raw = try runner.execRead(allocator, &.{ "b2sum", hostEfiPath });
        defer allocator.free(raw);

        const hash_end = std.mem.indexOfScalar(u8, raw, ' ') orelse return error.UnexpectedB2sumOutput;
        return allocator.dupe(u8, raw[0..hash_end]);
    }
};
