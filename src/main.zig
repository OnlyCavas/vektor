const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli");

const Parser = cli.Parser;
const ParserError = Parser.ParserError;
const Action = cli.Action;

pub fn main(init: std.process.Init.Minimal) !u8 {
    const use_gpa = builtin.mode == .Debug;
    var gpa: std.heap.DebugAllocator(.{}) = .init;

    defer if (use_gpa) {
        _ = gpa.deinit();
    };
    const allocator = if (use_gpa) gpa.allocator() else std.heap.smp_allocator;

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    return blk: {
        var parser: Parser = .init(init.args);
        const action = (parser.parse() catch |err| break :blk err) orelse Action.help;

        break :blk action.run(.{
            .allocator = allocator,
            .io = io,
        }, &parser);
    } catch |err| blk: {
        var err_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, &err_buffer);
        const stdout = &stdout_writer.interface;

        switch (err) {
            ParserError.InvalidAction => {
                try stdout.writeAll(
                    \\error: unrecognized option
                    \\
                    \\Run 'vektor --help' for more information.
                );
            },
            ParserError.InvalidValue => {
                try stdout.writeAll(
                    \\error: invalid value
                    \\
                    \\Run 'vektor --help' for more information.
                );
            },

            else => try stdout.print("unknown error {}", .{err}),
        }

        try stdout.writeByte('\n');
        try stdout.flush();
        break :blk 1;
    };
}
