const std = @import("std");

const Runner = @import("utils").Runner;
const InstallConfig = @import("config").InstallConfig;

const basetrap = @import("basetrap.zig");
const disk = @import("disk.zig");

const modules = .{ disk, basetrap };

pub fn runAll(runner: *Runner, cfg: InstallConfig) !void {
    inline for (modules) |m| {
        m.run(runner, cfg) catch |err| {
            std.debug.print("step: {s} failed \n", .{m.label});

            return err;
        };
    }
}
