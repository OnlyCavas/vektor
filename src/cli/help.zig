const std = @import("std");
const cli = @import("cli");

const Ctx = cli.Ctx;
const Allocator = std.mem.Allocator;
const Parser = cli.Parser;
const Action = cli.Action;

/// @vektor Show this help message.
/// @example vektor help
/// @example vektor --help
pub fn run(ctx: *const Ctx, parser: *Parser) !u8 {
    _ = parser;

    const io = ctx.io;

    var buffer: [2048]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    const stdout = &writer.interface;

    try stdout.writeAll(
        \\USAGE:
        \\  vektor [OPTIONS] <COMMAND>
        \\
        \\
    );

    try stdout.writeAll(
        \\COMMANDS:
        \\
    );

    const max_len = comptime blk: {
        var max = 0;

        for (@typeInfo(Action).@"enum".fields) |cmd| {
            if (cmd.name.len > max) max = cmd.name.len;
        }

        break :blk max;
    };

    inline for (@typeInfo(Action).@"enum".fields) |cmds| {
        const action: Action = @enumFromInt(cmds.value);

        try stdout.print("  {[name]s:<[width]}          {[desc]s}\n", .{
            .name = cmds.name,
            .width = max_len,
            .desc = action.description(),
        });
    }

    try stdout.writeAll(
        \\
        \\EXAMPLES:
        \\
    );

    inline for (@typeInfo(Action).@"enum".fields) |cmds| {
        const action: Action = @enumFromInt(cmds.value);

        if (action.examples()) |example| {
            var lines = std.mem.splitScalar(u8, example, '\n');

            while (lines.next()) |line| {
                try stdout.print("  {s}\n", .{line});
            }
        } else |_| {}
    }

    try stdout.flush();

    return 0;
}
