const std = @import("std");

const config = @import("config");

const DotfileConfig = config.DotfilesConfig;

const Repositories = @import("components/repositories.zig").Repositories;
const WindowManager = @import("components/windowManager.zig").WindowManager;

const Ctx = @import("lib.zig").Context;
const Runner = @import("utils").Runner;

pub const label = "Extra - System Configuration";

pub const installPackages: config.PackageSpec = .{
    .base = &.{"git"},
    .services = &.{},
};

pub const installComponents = .{
    Repositories,
    WindowManager,
};

pub fn run(ctx: *const Ctx) !void {
    const runner = ctx.runner;
    const cfg = ctx.cfg;

    var arena: std.heap.ArenaAllocator = .init(ctx.runner.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for (cfg.system.users) |user| {
        if (user.dotfiles) |dotfiles| {
            const dotfilesDest = try std.fmt.allocPrint(allocator, "/home/{s}/dotfiles", .{user.name});
            defer allocator.free(dotfilesDest);

            try cloneDotfiles(runner, dotfiles, dotfilesDest);
        }
    }

    // TODO execute the dotfiles to be installed
    // TODO instead of cloning the dotfiles at runtime, embed them at compile time
}

fn cloneDotfiles(runner: *Runner, dotfiles: DotfileConfig, path: []const u8) !void {
    try runner.execChroot(&.{ "git", "init", path });
    try runner.execChroot(&.{ "git", "-C", path, "remote", "add", "origin", dotfiles.git });

    return if (dotfiles.commit) |commit| {
        try runner.execChroot(&.{ "git", "-C", path, "fetch", "--depth", "1", "origin", commit });
        try runner.execChroot(&.{ "git", "-C", path, "checkout", "FETCH_HEAD" });
    } else {
        try runner.execChroot(&.{ "git", "-C", path, "fetch", "--depth", "1", "origin", "HEAD" });
        try runner.execChroot(&.{ "git", "-C", path, "checkout", "FETCH_HEAD" });
    };
}
