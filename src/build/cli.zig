const Cli = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const Token = std.zig.Token;
const Writer = std.Io.Writer;

module: *std.Build.Module,

const CliWalker = struct {
    arena: std.heap.ArenaAllocator,
    cmds: std.ArrayList(Command),

    pub const CommandError = error{
        FailToParse,
    };

    const Extracted = struct {
        description: []const u8,
        flags: []const Flag,
    };

    pub const Flag = struct {
        name: []const u8,
        short: ?[]const u8 = null,
        description: ?[]const u8,
        docTags: DocTags,

        fn init(allocator: Allocator, name: []const u8, payload: []const u8) !Flag {
            const docTags: DocTags = try .extract(allocator, payload);

            return .{
                .name = name,
                .short = docTags.find("short"),
                .description = docTags.find("description"),
                .docTags = docTags,
            };
        }
    };

    pub const Command = struct {
        name: []const u8,
        description: []const u8,
        path: []const u8,
        docTags: DocTags,
        flags: []const Flag,

        fn parse(allocator: Allocator, payload: []const u8, path: []const u8, flags: []const Flag) !Command {
            const zigIdx = std.mem.indexOf(u8, path, ".zig") orelse return CommandError.FailToParse;
            const slashIdx = std.mem.lastIndexOf(u8, path, "/") orelse return CommandError.FailToParse;
            const docTags: DocTags = try .extract(allocator, payload);

            return .{
                .name = path[slashIdx + 1 .. zigIdx],
                .description = docTags.find("vektor") orelse return CommandError.FailToParse,
                .path = path,
                .docTags = docTags,
                .flags = flags,
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

            const source_path = try std.fs.path.join(allocator, &.{ core_dir, item.path });
            const payload = try core.readFileAlloc(io, item.path, allocator, .unlimited);
            const cmd = try parse(allocator, source_path, payload) orelse continue;

            try self.cmds.append(allocator, cmd);
        }
    }

    fn parse(allocator: Allocator, path: []const u8, raw: []const u8) !?Command {
        const source = try allocator.dupeZ(u8, raw);
        defer allocator.free(source);

        var astree = try std.zig.Ast.parse(allocator, source, .zig);
        defer astree.deinit(allocator);

        var root_buf: [2]std.zig.Ast.Node.Index = undefined;
        const root_decl = astree.fullContainerDecl(&root_buf, .root) orelse return null;

        const result = try extract(allocator, astree, root_decl) orelse return null;
        defer allocator.free(result.description);

        return try Command.parse(allocator, try allocator.dupe(u8, result.description), path, result.flags);
    }

    fn extract(allocator: Allocator, astree: Ast, root_decl: Ast.full.ContainerDecl) !?Extracted {
        var description: ?[]const u8 = null;
        var flags: std.ArrayList(Flag) = .empty;
        defer flags.deinit(allocator);

        for (root_decl.ast.members) |idx| {
            var fn_buf: [1]std.zig.Ast.Node.Index = undefined;

            if (astree.fullFnProto(&fn_buf, idx)) |fn_proto| {
                const c = extractFn(allocator, astree, fn_proto) catch continue;
                if (description) |old| allocator.free(old);
                description = c;

                continue;
            }

            const root_var = astree.fullVarDecl(idx) orelse continue;
            const init_node = root_var.ast.init_node.unwrap() orelse continue;

            var inner_buf: [2]std.zig.Ast.Node.Index = undefined;
            const container_decl = astree.fullContainerDecl(&inner_buf, init_node) orelse continue;

            const anchor = root_var.visib_token orelse root_var.ast.mut_token - 1;
            const struct_doc = (try extractDoc(allocator, astree, anchor)) orelse continue;

            // ignore if doesn't have @flags
            if (!std.mem.eql(u8, std.mem.trim(u8, struct_doc, " \t\r"), "@flags")) continue;

            for (container_decl.ast.members) |member| {
                if (astree.fullContainerField(member)) |field| {
                    const f_name = astree.tokenSlice(field.ast.main_token);
                    const f_comment = extractStruct(allocator, astree, field) catch continue;

                    try flags.append(allocator, try Flag.init(
                        allocator,
                        try allocator.dupe(u8, f_name),
                        f_comment,
                    ));
                }
            }
        }

        return .{
            .description = description orelse return null,
            .flags = try flags.toOwnedSlice(allocator),
        };
    }

    fn extractFn(allocator: Allocator, astree: Ast, fn_proto: Ast.full.FnProto) ![]const u8 {
        const anchor = fn_proto.visib_token orelse fn_proto.ast.fn_token;
        return (try extractDoc(allocator, astree, anchor)) orelse error.NoDocComment;
    }

    fn extractStruct(allocator: Allocator, astree: Ast, field: Ast.full.ContainerField) ![]const u8 {
        const anchor = field.ast.main_token;
        return (try extractDoc(allocator, astree, anchor)) orelse error.NoDocComment;
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
) !?[]const u8 {
    const tokens = astree.tokens.items(.tag);

    const start_index: usize = start_index: for (0..index) |i| {
        const r_index = index - i - 1;
        const token = tokens[r_index];

        if (token != .doc_comment)
            break :start_index r_index + 1;
    } else 0;

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

fn genActions(allocator: Allocator, cmds: []const CliWalker.Command) ![]const u8 {
    var wAlloc: Writer.Allocating = .init(allocator);
    defer wAlloc.deinit();

    try wAlloc.writer.writeAll(
        \\const Self = @This();
        \\
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\
        \\const args = @import("args.zig");
        \\pub const Parser = args.Parser;
        \\
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("const {s} = @import(\"{s}\");\n", .{ cmd.name, cmd.name });
    }

    try wAlloc.writer.writeAll(
        \\
        \\pub const Option = struct {
        \\    name: []const u8,
        \\    short: ?[]const u8 = null,
        \\    description: ?[]const u8 = null,
        \\};
        \\
        \\pub const Ctx = struct {
        \\    allocator: Allocator,
        \\    io: std.Io,
        \\};
        \\
        \\var _action: ?Action = null;
        \\
        \\pub fn action() ?Action {
        \\  return Self._action;
        \\}
        \\
        \\pub const Action = enum {
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("    {s},\n", .{cmd.name});
    }

    try wAlloc.writer.writeAll(
        \\
        \\    pub fn detectHelp(arg: []const u8) ?Action {
        \\        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        \\            return .help;
        \\        }
        \\
        \\        return null;
        \\    }
        \\
        \\    pub fn run(self: Action, ctx: Ctx, parser: *Parser) !u8 {
        \\        Self._action = self;
        \\
        \\        return self.runCmd(&ctx, parser) catch |err| switch (err) {
        \\            help_error => err: {
        \\                inline for (@typeInfo(Action).@"enum".fields) |cmd| {
        \\                    if (std.mem.eql(u8, cmd.name, @tagName(self))) {
        \\                        var buffer: [1024]u8 = undefined;
        \\                        var writer = std.Io.File.stdout().writer(ctx.io, &buffer);
        \\                        const stdout = &writer.interface;
        \\
        \\                        try stdout.print(
        \\                            \\{s}
        \\                            \\
        \\                            \\
        \\                        , .{self.description()});
        \\
        \\                        try stdout.print(
        \\                            \\USAGE:
        \\                            \\  vektor {s} [OPTIONS]
        \\                            \\
        \\                        , .{cmd.name});
        \\
        \\
        \\                        const opts = self.options();
        \\
        \\                        if (opts.len != 0) {
        \\                            try stdout.writeAll(
        \\                              \\
        \\                              \\OPTIONS:
        \\                              \\
        \\                            );
        \\                        }
        \\
        \\                        for (opts) |opt| {
        \\                            try stdout.writeAll("   ");
        \\
        \\                            if (opt.short) |short|
        \\                               try stdout.print("-{s}, ", .{short});
        \\
        \\                            try stdout.print("--{s}", .{opt.name});
        \\
        \\                            if (opt.description) |desc|
        \\                               try stdout.print("   {s}", .{desc});
        \\
        \\                            try stdout.writeAll("\n");
        \\                        }
        \\
        \\                        if (self.examples()) |example| {
        \\                            try stdout.writeAll(
        \\                                \\
        \\                                \\EXAMPLES:
        \\                                \\
        \\                            );
        \\
        \\                            var lines = std.mem.splitScalar(u8, example, '\n');
        \\                            while (lines.next()) |line| {
        \\                                try stdout.print("  {s}\n", .{line});
        \\                            }
        \\                        } else |_| {}
        \\
        \\                        try stdout.flush();
        \\
        \\                        break :err 0;
        \\                    }
        \\                }
        \\
        \\                break :err err;
        \\            },
        \\            else => err,
        \\        };
        \\    }
        \\
        \\    pub const help_error = error.help_error;
        \\
        \\    pub fn runCmd(self: Action, ctx: *const Ctx, parser: *Parser) !u8 {
        \\        return switch (self) {
        \\
    );

    for (cmds) |cmd| {
        try wAlloc.writer.print("            .{s} => try {s}.run(ctx, parser),\n", .{ cmd.name, cmd.name });
    }

    try wAlloc.writer.writeAll(
        \\        };
        \\    }
        \\
        \\
    );

    try genCliStrings(allocator, &wAlloc.writer, cmds);

    try wAlloc.writer.writeAll("};");
    return wAlloc.toOwnedSlice();
}

fn genCliStrings(allocator: Allocator, writer: *Writer, cmds: []const CliWalker.Command) !void {
    try writer.writeAll(
        \\    pub fn description(self: Action) []const u8 {
        \\        return switch (self) {
        \\
    );

    for (cmds) |cmd| {
        try writer.print("            .{s} => \"", .{cmd.name});
        try std.zig.stringEscape(cmd.description, writer);
        try writer.writeAll("\",\n");
    }

    try writer.writeAll(
        \\        };
        \\    }
        \\
        \\
    );

    try writer.writeAll(
        \\    pub fn examples(self: Action) ![]const u8 {
        \\        return switch (self) {
        \\
    );

    var needs_else = false;
    for (cmds) |cmd| {
        const docs = try cmd.docTags.findAll(allocator, "example");
        if (docs.len == 0) {
            needs_else = true;
            continue;
        }

        try writer.print("            .{s} =>\n", .{cmd.name});

        for (docs) |example| {
            try writer.print("                \\\\{s}\n", .{example});
        }

        try writer.writeAll("            ,\n");
    }

    if (needs_else)
        try writer.writeAll("            else => error.NoExamples,\n");

    try writer.writeAll(
        \\        };
        \\    }
        \\
        \\
    );

    try writer.writeAll(
        \\    pub fn options(self: Action) []const Option {
        \\        return switch (self) {
        \\
    );

    for (cmds) |cmd| {
        try writer.print("            .{s} => &. {{\n", .{cmd.name});

        for (cmd.flags) |flag| {
            try writer.print(
                "              .{{ .name = \"{s}\"",
                .{flag.name},
            );

            if (flag.description) |description|
                try writer.print(", .description = \"{s}\"", .{description});

            if (flag.short) |short|
                try writer.print(", .short = \"{s}\"", .{short});

            try writer.writeAll("},\n");
        }

        try writer.writeAll("            },\n");
    }

    try writer.writeAll(
        \\        };
        \\    }
        \\
        \\
    );
}

pub fn init(b: *std.Build, vektor: *std.Build.Module) !Cli {
    const core_dir: []const u8 = "./src/cli";

    var arena_alloc: std.heap.ArenaAllocator = .init(b.allocator);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    const wfs = b.addWriteFiles();

    var walker: CliWalker = .init(allocator);
    defer walker.deinit(allocator);

    try walker.walkDir(core_dir);

    const action_payload = try genActions(allocator, walker.cmds.items);
    const cli_lib_file = wfs.add("cli.zig", action_payload);

    _ = wfs.addCopyFile(b.path("src/cli/args.zig"), "args.zig");

    const cli_module = b.createModule(.{
        .root_source_file = cli_lib_file,
    });

    for (walker.cmds.items) |cmd| {
        const cmd_module = b.createModule(.{
            .root_source_file = b.path(cmd.path),
        });

        cmd_module.addImport("vektor", vektor);
        cmd_module.addImport("cli", cli_module);
        cli_module.addImport(cmd.name, cmd_module);
    }

    return .{ .module = cli_module };
}

pub fn addImport(self: *const Cli, step: *std.Build.Step.Compile) !void {
    step.root_module.addImport("cli", self.module);
}
