const std = @import("std");
const builtin = @import("builtin");

const lib = @import("lib");
const utils = @import("utils");

const ArtixConfiguration = @import("config").Config;

// TODO I need to be sure, that every tooling effectely exists
// NOTE Before using like [limine], check if is actually installed, if not error
// NOTE Write tests, would be actually cool

pub fn main(init: std.process.Init.Minimal) !void {
    const use_gpa = builtin.mode == .Debug;

    var gpa: std.heap.DebugAllocator(.{}) = .init;

    defer if (use_gpa) {
        _ = gpa.deinit();
    };

    const allocator = if (use_gpa)
        gpa.allocator()
    else
        std.heap.smp_allocator;

    var dry_run = false;
    var args = init.args.iterate();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run")) dry_run = true;
    }

    var runner: utils.Runner = try .init(allocator, init.environ, .{
        .dry_run = dry_run,
        .log_file_path = "/tmp/artix-installer.log",
    });

    defer runner.deinit();

    lib.install(&runner, ArtixConfiguration) catch {
        std.process.exit(1);
    };
}
