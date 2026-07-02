const std = @import("std");

const config = @import("config");

const Bootloader = @import("components/bootloader.zig").Bootloader;
const Hardware = @import("components/hardware.zig").Hardware;
const PriviledgeEscalation = @import("components/priviled_escalation.zig").PrivelidgeEscalation;

const Ctx = @import("lib.zig").Context;
const Runner = @import("utils").Runner;

pub const label = "Installation";

pub const installPackages: config.PackageSpec = .{
    .base = &.{ "base", "base-devel", "linux-firmware", "sof-firmware" },
    .services = &.{ "elogind", "networkmanager" },
};

pub const installComponents = .{
    Hardware,
    PriviledgeEscalation,
    Bootloader,
};

pub fn run(ctx: *const Ctx) !void {
    var arena: std.heap.ArenaAllocator = .init(ctx.runner.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // setup mirriors

    try startServices(ctx);
    try installSystem(ctx.runner, allocator, ctx.packages);

    try fstab(ctx.runner, allocator);

    try configureSystem(ctx.runner, allocator, ctx.cfg.system);
    try configureUsers(ctx.runner, allocator, ctx.cfg.system);
}

fn startServices(ctx: *const Ctx) !void {
    const systemClock = switch (ctx.cfg.packages.initSystem) {
        .dinit, .openrc => "ntpd",
        .runit, .s6 => "openntpd",
    };

    try ctx.services().start(systemClock);
}

fn installSystem(runner: *Runner, allocator: std.mem.Allocator, packages: []const []const u8) !void {
    const argv = try std.mem.concat(
        allocator,
        []const u8,
        &.{ &.{ "basestrap", "/mnt" }, packages },
    );

    try runner.exec(argv);
}

fn fstab(runner: *Runner, allocator: std.mem.Allocator) !void {
    const out = try runner.execRead(allocator, &.{ "fstabgen", "-U", "/mnt" });
    defer allocator.free(out);

    try runner.writeFile("/mnt/etc/fstab", out);
}

fn configureSystem(runner: *Runner, allocator: std.mem.Allocator, system: config.SystemConfig) !void {
    const zone = try std.fmt.allocPrint(allocator, "/usr/share/zoneinfo/{s}", .{system.timezone});
    try runner.execChroot(&.{ "ln", "-sf", zone, "/etc/localtime" });
    try runner.execChroot(&.{ "hwclock", "--systohc" });

    const gen = try std.fmt.allocPrint(allocator, "{s} UTF-8\n", .{system.locale});
    try runner.writeFile("/mnt/etc/locale.gen", gen);
    try runner.execChroot(&.{"locale-gen"});

    const conf = try std.fmt.allocPrint(allocator, "LANG={s}\n", .{system.locale});
    try runner.writeFile("/mnt/etc/locale.conf", conf);

    const vconsole = try std.fmt.allocPrint(allocator, "KEYMAP={s}\n", .{system.keymap});
    try runner.writeFile("/mnt/etc/vconsole.conf", vconsole);

    const host = try std.fmt.allocPrint(allocator, "{s}\n", .{system.hostname});
    try runner.writeFile("/mnt/etc/hostname", host);
}

fn configureUsers(runner: *Runner, allocator: std.mem.Allocator, system: config.SystemConfig) !void {
    try setPassword(runner, allocator, "root");
    try runner.execChroot(&.{ "passwd", "-l", "root" });

    for (system.users) |user| {
        const groups = try std.mem.join(allocator, ",", user.groups);
        defer allocator.free(groups);

        try runner.execChroot(&.{ "useradd", "-m", "-s", user.shell.path(), "-G", groups, user.name });
        try setPassword(runner, allocator, user.name);
    }
}

fn setPassword(runner: *Runner, allocator: std.mem.Allocator, name: []const u8) !void {
    if (runner.options.dry_run) return;

    var pw_buf: [128]u8 = undefined;
    defer std.crypto.secureZero(u8, &pw_buf);

    const prompt = try std.fmt.allocPrint(allocator, "password for {s}: ", .{name});
    defer allocator.free(prompt);
    const pw = try readPassword(prompt, &pw_buf);

    var line_buf: [256]u8 = undefined;
    defer std.crypto.secureZero(u8, &line_buf);
    const line = try std.fmt.bufPrint(&line_buf, "{s}:{s}\n", .{ name, pw });

    try runner.execInput(&.{ "artix-chroot", "/mnt", "chpasswd" }, line);
}

fn readPassword(prompt: []const u8, out: []u8) ![]const u8 {
    const posix = std.posix;
    const fd = posix.STDIN_FILENO;

    std.debug.print("{s}", .{prompt});

    const original = try posix.tcgetattr(fd);
    var raw = original;
    raw.lflag.ECHO = false;
    try posix.tcsetattr(fd, .FLUSH, raw);
    defer posix.tcsetattr(fd, .FLUSH, original) catch {};

    const n = try posix.read(fd, out);
    std.debug.print("\n", .{});

    var len = n;
    if (len > 0 and out[len - 1] == '\n') len -= 1;

    return out[0..len];
}
