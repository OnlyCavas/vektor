const std = @import("std");
const builtin = @import("builtin");
const steps = @import("steps.zig");

const InstallConfig = @import("config").Config;
const Runner = @import("cwd").Runner;

// TODO I need to be sure, that every tooling effectely exists
// NOTE Before using like [limine], check if is actually installed, if not error
// NOTE Write tests, would be actually cool

pub fn main(init: std.process.Init.Minimal) !void {
    var dry_run: bool = false;
    var log_file_path: []const u8 = "/tmp/artix-installer.log";

    const use_gpa = builtin.mode == .Debug;
    var gpa: std.heap.DebugAllocator(.{}) = .init;

    var args = init.args.iterate();

    defer if (use_gpa) {
        _ = gpa.deinit();
    };

    const allocator = if (use_gpa)
        gpa.allocator()
    else
        std.heap.smp_allocator;

    var threaded: std.Io.Threaded = .init(allocator, .{ .environ = init.environ });
    defer threaded.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        }

        if (std.mem.eql(u8, arg, "--log-file")) {
            log_file_path = args.next() orelse return error.MissingArgument;
        }
    }

    var runner: Runner = try .init(threaded.io(), .{
        .dry_run = dry_run,
        .log_file_path = log_file_path,
    });
    defer runner.deinit();

    steps.install(allocator, &runner, InstallConfig) catch |e| {
        var buf: [1024]u8 = undefined;
        runner.logger.err(&buf, "installation failed: {s}\n", .{@errorName(e)}) catch {};

        std.process.exit(1);
    };
}
