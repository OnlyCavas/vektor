const std = @import("std");
const builtin = @import("builtin");
const vektor = @import("vektor");
const cli = @import("cli");

const Parser = cli.Parser;
const Action = cli.Action;

pub fn main(init: std.process.Init.Minimal) !void {
    const use_gpa = builtin.mode == .Debug;
    var gpa: std.heap.DebugAllocator(.{}) = .init;

    defer if (use_gpa) {
        _ = gpa.deinit();
    };
    const allocator = if (use_gpa) gpa.allocator() else std.heap.smp_allocator;

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    vektor.init(.{
        .gpa_allocator = allocator,
        .io = threaded.io(),
    });

    var parser: Parser = .init(init.args);
    const action = try parser.parse() orelse Action.help;

    std.process.exit(action.run(allocator, vektor.io(), &parser) catch |err| err: {
        std.log.err("failed with {}", .{err});
        break :err 1;
    });
}
