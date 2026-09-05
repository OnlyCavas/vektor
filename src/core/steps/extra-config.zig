const std = @import("std");
const config_types = @import("config_types");

const DotfileConfig = config_types.DotfilesConfig;
const PackageSpec = config_types.PackageSpec;

const Repositories = @import("components/repositories.zig").Repositories;
const WindowManager = @import("components/windowManager.zig").WindowManager;

const Ctx = @import("lib.zig").Context;
const Runner = @import("cwd").Runner;

pub const label = "Extra - System Configuration";

pub const installPackages: PackageSpec = .{
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

    var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try runner.execChroot(allocator, &.{ "fc-cache", "-f" });

    // TODO add apparmour profiles and set them properly

    // TODO prepare first boot script
    //      1. toogle global sys update
    //      2. prepare lynis report
}
