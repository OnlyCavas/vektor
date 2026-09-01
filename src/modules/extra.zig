const std = @import("std");

const config = @import("config");

const DotfileConfig = config.DotfilesConfig;

const Repositories = @import("components/repositories.zig").Repositories;
const WindowManager = @import("components/windowManager.zig").WindowManager;

const Ctx = @import("lib.zig").Context;
const Runner = @import("utils").Runner;

pub const label = "Extra - System Configuration";

pub const installPackages: config.PackageSpec = .{
    .base = &.{
        "git",
        "ttf-jetbrains-mono-nerd",
        "noto-fonts",
        "noto-fonts-emoji",
    },
};

pub const installComponents = .{
    Repositories,
    WindowManager,
};

pub fn run(ctx: *const Ctx) !void {
    const runner = ctx.runner;

    var arena: std.heap.ArenaAllocator = .init(ctx.runner.allocator);
    defer arena.deinit();

    try runner.execChroot(&.{ "fc-cache", "-f" });

    // TODO add apparmour profiles and set them properly

    // TODO prepare first boot script
    //      1. toogle global sys update
    //      2. prepare lynis report
}
