const std = @import("std");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Child = std.process.Child;
const File = std.Io.File;

pub const Logger = struct {
    io: std.Io,
    file: File,
    path: []const u8,

    pub fn init(io: std.Io, path: []const u8) !Logger {
        const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
        return .{ .io = io, .file = file, .path = path };
    }

    pub fn deinit(self: Logger) void {
        self.file.close(self.io);
    }

    fn printLine(self: Logger, target: File, buf: []u8, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        var writer = target.writerStreaming(self.io, buf);
        try writer.interface.print(fmt, args);
        try writer.interface.flush();
    }

    pub fn info(self: Logger, buf: []u8, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        try self.printLine(.stdout(), buf, fmt ++ "\n", args);
    }

    pub fn err(self: Logger, buf: []u8, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        try self.printLine(.stdout(), buf, fmt ++ "\n check log: {s}\n", args ++ .{self.path});
    }

    pub fn both(self: Logger, buf: []u8, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        try self.printLine(.stdout(), buf, fmt, args);
        try self.printLine(self.file, buf, fmt, args);
    }
};

pub const Runner = struct {
    io: std.Io,
    logger: Logger,
    options: RunnerOptions,

    pub const ExecError = error{
        CommandFailed,
    } || std.mem.Allocator.Error || std.process.SpawnError || std.Io.Writer.Error || std.Io.Reader.Error;

    pub const RunnerOptions = struct {
        dry_run: bool = false,
        log_file_path: []const u8 = "/var/log/artix-installer.log",
    };

    pub fn init(io: std.Io, options: RunnerOptions) !Runner {
        return .{
            .io = io,
            .logger = try Logger.init(io, options.log_file_path),
            .options = options,
        };
    }

    pub fn deinit(self: Runner) void {
        self.logger.deinit();
    }

    fn printLine(io: std.Io, file: File, buf: []u8, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        var writer = file.writerStreaming(io, buf);
        try writer.interface.print(fmt, args);
        try writer.interface.flush();
    }

    fn logCommand(self: Runner, allocator: Allocator, argv: []const []const u8) ExecError!bool {
        const joined = try std.mem.join(allocator, " ", argv);
        defer allocator.free(joined);

        var buf: [1024]u8 = undefined;
        try self.logger.info(&buf, "$ {s}", .{joined});

        if (self.options.dry_run) return false;

        try self.logger.printLine(self.logger.file, &buf, "$ {s}\n", .{joined});
        return true;
    }

    fn evaluateExec(
        self: Runner,
        allocator: Allocator,
        term: Child.Term,
        argv: []const []const u8,
    ) ExecError!void {
        var buf: [1024]u8 = undefined;

        switch (term) {
            .exited => |code| if (code != 0) {
                const joined = try std.mem.join(allocator, " ", argv);
                defer allocator.free(joined);

                try self.logger.err(&buf, "command failed (exit {d}): {s}\n check log: {s}\n", .{
                    code,
                    joined,
                    self.options.log_file_path,
                });

                return error.CommandFailed;
            },
            else => {
                try self.logger.err(
                    &buf,
                    "command terminated abnormally\n check log: {s}\n",
                    .{self.options.log_file_path},
                );

                return error.CommandFailed;
            },
        }
    }

    pub fn exec(self: Runner, allocator: Allocator, argv: []const []const u8) ExecError!void {
        if (!try self.logCommand(allocator, argv)) return;

        var child = try std.process.spawn(
            self.io,
            .{
                .argv = argv,
                .stdout = .{ .file = self.logger.file },
                .stderr = .{ .file = self.logger.file },
            },
        );

        const term = try child.wait(self.io);
        return self.evaluateExec(allocator, term, argv);
    }

    pub fn execInput(self: Runner, allocator: Allocator, argv: []const []const u8, input: []const u8) !void {
        if (!try self.logCommand(allocator, argv)) return;

        var child = try std.process.spawn(
            self.io,
            .{
                .argv = argv,
                .stdin = .pipe,
                .stdout = .{ .file = self.logger.file },
                .stderr = .{ .file = self.logger.file },
            },
        );

        var buf: [4096]u8 = undefined;

        const stdin: File = child.stdin orelse {
            try self.logger.info(&buf, "failed to fetch stdin", .{});
            return error.CommandFailed;
        };

        var stdin_writer = stdin.writerStreaming(self.io, &buf);
        try stdin_writer.interface.writeAll(input);
        try stdin_writer.interface.flush();

        stdin.close(self.io);

        const term = try child.wait(self.io);
        try self.evaluateExec(allocator, term, argv);
    }

    pub fn execRead(self: Runner, allocator: Allocator, argv: []const []const u8) ExecError![]u8 {
        if (!try self.logCommand(allocator, argv)) return try allocator.dupe(u8, "no runtime value");

        var child = try std.process.spawn(
            self.io,
            .{
                .argv = argv,
                .stdout = .pipe,
                .stderr = .{ .file = self.logger.file },
            },
        );

        var buf: [4096]u8 = undefined;

        const stdout: File = child.stdout orelse {
            try self.logger.info(&buf, "failed to fetch stdout", .{});
            return error.CommandFailed;
        };

        var stdout_reader = stdout.readerStreaming(self.io, &buf);

        var sink: Writer.Allocating = .init(allocator);
        defer sink.deinit();

        _ = try stdout_reader.interface.streamRemaining(&sink.writer);

        const term = try child.wait(self.io);
        try self.evaluateExec(allocator, term, argv);

        return try sink.toOwnedSlice();
    }

    pub fn execChroot(self: Runner, allocator: Allocator, argv: []const []const u8) ExecError!void {
        var chroot: std.ArrayList([]const u8) = try .initCapacity(allocator, argv.len + 2);
        defer chroot.deinit(allocator);

        chroot.appendSliceAssumeCapacity(&.{ "artix-chroot", "/mnt" });
        chroot.appendSliceAssumeCapacity(argv);

        try self.exec(allocator, chroot.items);
    }

    pub fn writeFile(self: Runner, allocator: Allocator, path: []const u8, payload: []const u8) !void {
        const payloadPrint = try std.fmt.allocPrint(allocator, "\n{s}\n", .{payload});
        defer allocator.free(payloadPrint);

        if (!try self.logCommand(allocator, &.{ "write", path, payloadPrint })) return;

        const cwd = std.Io.Dir.cwd();

        if (std.fs.path.dirname(path)) |dirPath|
            try cwd.createDirPath(self.io, dirPath);

        const file = try cwd.createFile(self.io, path, .{});
        defer file.close(self.io);

        var fileBuffer: [4096]u8 = undefined;
        var fileWriter = file.writerStreaming(self.io, &fileBuffer);
        try fileWriter.interface.writeAll(payload);
        try fileWriter.flush();
    }

    pub fn appendToFile(self: Runner, allocator: Allocator, path: []const u8, payload: []const u8) !void {
        const payloadPrint = try std.fmt.allocPrint(allocator, "\n{s}\n\n", .{payload});
        defer allocator.free(payloadPrint);

        if (!try self.logCommand(allocator, &.{ "append", path, payloadPrint })) return;

        const cwd = std.Io.Dir.cwd();

        const file: File = try cwd.createFile(self.io, path, .{ .truncate = true });
        defer file.close(self.io);

        const end = try file.length(self.io);
        try file.writePositionalAll(self.io, payload, end);
    }
};
