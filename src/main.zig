const std = @import("std");
const lib = @import("lib");

const utils = @import("utils");

const ArtixConfiguration = @import("config").Config;

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

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
