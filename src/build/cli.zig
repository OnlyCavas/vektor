const Cli = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

module: *std.Build.Module,

const CliWalker = struct {
    arena: std.heap.ArenaAllocator,
    cmds: std.ArrayList(Command),

    pub const Command = struct {
        name: []const u8,
        description: []const u8,
        path: []const u8,
        docTags: DocTags,

        pub const CommandError = error{
            FailToParse,
        };

        fn parse(allocator: Allocator, payload: []const u8, path: []const u8) !Command {
            const zigIdx = std.mem.indexOf(u8, path, ".zig") orelse return CommandError.FailToParse;
            const docTags: DocTags = try .extract(allocator, payload);

            return .{
                .name = path[0..zigIdx],
                .description = docTags.find("vektor") orelse return CommandError.FailToParse,
                .path = path,
                .docTags = docTags,
            };
        }
    };

    fn init(allocator: Allocator) CliWalker {
        return .{ .arena = .init(allocator), .cmds = .empty };
    }

    fn deinit(self: *CliWalker, allocator: Allocator) void {
        self.arena.deinit();
        self.cmds.deinit(allocator);
    }

    fn walkDir(
        self: *CliWalker,
        b: *std.Build,
        wfs: *std.Build.Step.WriteFile,
        core_dir: []const u8,
    ) !void {
        const allocator = self.arena.allocator();

        var threaded: std.Io.Threaded = .init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const cwd = std.Io.Dir.cwd();
        const core = try cwd.openDir(io, core_dir, .{ .iterate = true });
        defer core.close(io);

        var walker = try core.walk(allocator);

        while (try walker.next(io)) |item| {
            if (item.kind != .file) continue;
            if (!std.mem.endsWith(u8, item.path, ".zig")) continue;

            const src_path = try std.fs.path.join(allocator, &.{ core_dir, item.path });
            _ = wfs.addCopyFile(b.path(src_path), item.path);

            const raw = try core.readFileAlloc(io, item.path, allocator, .unlimited);
            const cmd = try parse(allocator, item.path, raw) orelse continue;

            try self.cmds.append(allocator, cmd);
        }
    }

    fn parse(allocator: Allocator, path: []const u8, raw: []const u8) !?Command {
        const source = try allocator.dupeZ(u8, raw);
        defer allocator.free(source);

        var astree = try std.zig.Ast.parse(allocator, source, .zig);
        defer astree.deinit(allocator);

        const tokens = astree.tokens.items(.tag);

        for (tokens, 0..) |token, index| {
            // TODO parse structs

            if (token != .keyword_fn) continue;

            const fn_name = astree.tokenSlice(@intCast(index + 1));
            if (!std.mem.eql(u8, fn_name, "run")) continue;

            if (index < 2 or tokens[index - 2] != .doc_comment) continue;

            const comment = try extractDoc(allocator, astree, @intCast(index - 2), tokens) orelse continue;

            return try Command.parse(allocator, comment, try allocator.dupe(u8, path));
        }

        return null;
    }
};

const DocTags = struct {
    items: []const Tag,

    pub const Tag = struct {
        key: []const u8,
        value: []const u8,
    };

    fn extract(allocator: Allocator, payload: []const u8) !DocTags {
        var tags: std.ArrayList(Tag) = .empty;
        defer tags.deinit(allocator);

        var lines = std.mem.splitScalar(u8, payload, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (trimmed.len == 0) continue;
            if (trimmed[0] != '@') continue;

            const rest = trimmed[1..];
            const keyEndIdx = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
            const key = rest[0..keyEndIdx];

            const value = rest[@min(keyEndIdx + 1, rest.len)..];

            try tags.append(allocator, .{
                .key = key,
                .value = value,
            });
        }

        return .{ .items = try tags.toOwnedSlice(allocator) };
    }

    fn find(self: DocTags, key: []const u8) ?[]const u8 {
        for (self.items) |tag| {
            if (std.mem.eql(u8, tag.key, key)) return tag.value;
        }

        return null;
    }

    fn findAll(self: DocTags, allocator: Allocator, key: []const u8) ![]const []const u8 {
        var values: std.ArrayList([]const u8) = .empty;
        defer values.deinit(allocator);

        for (self.items) |tag| {
            if (std.mem.eql(u8, tag.key, key)) try values.append(allocator, tag.value);
        }

        return values.toOwnedSlice(allocator);
    }
};

fn extractDoc(
    allocator: Allocator,
    astree: std.zig.Ast,
    index: std.zig.Ast.TokenIndex,
    tokens: []std.zig.Token.Tag,
) !?[]const u8 {
    const start_index: usize = start_index: for (0..index) |i| {
        const r_index = index - i - 1;
        const token = tokens[r_index];

        if (token != .doc_comment)
            break :start_index r_index + 1;
    } else unreachable;

    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);

    for (start_index..index + 1) |i| {
        const token = tokens[i];
        if (token != .doc_comment) continue;

        try lines.append(allocator, astree.tokenSlice(@intCast(i))[3..]);
    }

    if (lines.items.len == 0) return null;
    return try std.mem.join(allocator, "\n", lines.items);
}

fn genCliStrings(allocator: Allocator, cmds: []const CliWalker.Command) ![]const u8 {
    var wAlloc: Writer.Allocating = .init(allocator);
    defer wAlloc.deinit();

    try wAlloc.writer.writeAll(
        \\pub const Action = enum {
        \\
    );

    try wAlloc.writer.writeAll(
        \\    pub fn description(self: Action) []const u8 {
        \\        return switch (self) {
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("            .{s} => \"", .{cmd.name});
        try std.zig.stringEscape(cmd.description, &wAlloc.writer);
        try wAlloc.writer.writeAll("\",\n");
    }

    try wAlloc.writer.writeAll(
        \\        };
        \\    }
        \\
        \\
    );

    try wAlloc.writer.writeAll(
        \\    pub fn examples(self: Action) []const []const u8 {
        \\        return switch (self) {
        \\
    );

    for (cmds) |cmd| {
        const docs = try cmd.docTags.findAll(allocator, "example");
        if (docs.len == 0) continue;

        try wAlloc.writer.print("           .{s} =>\n", .{cmd.name});

        for (docs) |example| {
            try wAlloc.writer.print("           \\\\{s}\n", .{example});
        }

        try wAlloc.writer.writeAll("            ,\n");
    }

    try wAlloc.writer.writeAll(
        \\        };
        \\    }
        \\};
        \\
    );

    return wAlloc.toOwnedSlice();
}

fn genActions(allocator: Allocator, cmds: []const CliWalker.Command) ![]const u8 {
    var wAlloc: Writer.Allocating = .init(allocator);
    defer wAlloc.deinit();

    try wAlloc.writer.writeAll(
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\
        \\const args = @import("args.zig");
        \\pub const Parser = args.Parser;
        \\
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("const {s} = @import(\"{s}\");\n", .{ cmd.name, cmd.path });
    }

    try wAlloc.writer.writeAll(
        \\
        \\pub const Action = enum {
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("    {s},\n", .{cmd.name});
    }

    try wAlloc.writer.writeAll(
        \\
        \\    pub fn run(self: Action, allocator: Allocator, parser: *Parser) !u8 {
        \\        return self.runCmd(allocator, parser) catch |err| switch (err) {
        \\            else => err,
        \\        };
        \\    }
        \\
        \\    pub const help = error.help_error;
        \\
        \\    pub fn runCmd(self: Action, allocator: Allocator, parser: *Parser) !u8 {
        \\        return switch (self) {
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("            .{s} => try {s}.run(allocator, parser),\n", .{ cmd.name, cmd.name });
    }

    try wAlloc.writer.writeAll(
        \\        };
        \\    }
        \\
    );

    try wAlloc.writer.writeAll("};");
    return wAlloc.toOwnedSlice();
}

pub fn init(b: *std.Build) !Cli {
    const core_dir: []const u8 = "./src/cli";

    var arena_alloc: std.heap.ArenaAllocator = .init(b.allocator);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    const wfs = b.addWriteFiles();

    var walker: CliWalker = .init(allocator);
    defer walker.deinit(allocator);

    try walker.walkDir(b, wfs, core_dir);

    const action_payload = try genActions(allocator, walker.cmds.items);
    const cli_lib_file = wfs.add("cli.zig", action_payload);

    const cli_strings_payload = try genCliStrings(allocator, walker.cmds.items);
    const cli_strings_file = wfs.add("cli_string.zig", cli_strings_payload);

    const cli_module = b.createModule(.{
        .root_source_file = cli_lib_file,
    });

    cli_module.addAnonymousImport("cli_strings", .{
        .root_source_file = cli_strings_file,
    });

    return .{ .module = cli_module };
}

pub fn addImport(self: *const Cli, step: *std.Build.Step.Compile) !void {
    step.root_module.addImport("cli", self.module);
}
