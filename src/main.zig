const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli");

const Parser = cli.Parser;

pub fn main(init: std.process.Init.Minimal) !void {
    const use_gpa = builtin.mode == .Debug;
    var gpa: std.heap.DebugAllocator(.{}) = .init;

    defer if (use_gpa) {
        _ = gpa.deinit();
    };
    const allocator = if (use_gpa) gpa.allocator() else std.heap.smp_allocator;

    var parser: Parser = .init(init.args);
    const action = try parser.parse() orelse return error.NoAction;

    std.process.exit(action.run(allocator, &parser) catch |err| err: {
        std.log.err("failed with {}", .{err});
        break :err 1;
    });
}
