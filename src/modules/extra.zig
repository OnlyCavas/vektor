const std = @import("std");

const config = @import("config");

const Ctx = @import("lib.zig").Context;
const Runner = @import("utils").Runner;

pub const label = "Extra - System Configuration";

pub const installPackages: config.PackageSpec = .{
    .base = &.{},
    .services = &.{},
};

pub const installComponents = .{};

pub fn run(ctx: *const Ctx) !void {
    var arena: std.heap.ArenaAllocator = .init(ctx.runner.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = allocator;

    // configure the rest of the system, through components
    // if defined fetch the dotfiles
    // lock at commit
    // execute dotfiles configuration
}
