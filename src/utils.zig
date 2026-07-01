const std = @import("std");

const Child = std.process.Child;

pub const ExecError = error{
    CommandFailed,
} || std.mem.Allocator.Error || std.process.SpawnError || std.Io.Writer.Error || std.Io.Reader.Error;

pub const RunnerOptions = struct {
    dry_run: bool = false,
    log_file_path: []const u8 = "/var/log/artix-installer.log",
};

pub const Runner = struct {
    _threaded: std.Io.Threaded,
    allocator: std.mem.Allocator,
    _log: std.Io.File,
    options: RunnerOptions,

    pub fn init(allocator: std.mem.Allocator, environ: std.process.Environ, options: RunnerOptions) !Runner {
        var threaded: std.Io.Threaded = .init(allocator, .{ .environ = environ });

        const log = try std.Io.Dir.createFileAbsolute(
            threaded.io(),
            options.log_file_path,
            .{},
        );

        return .{
            ._threaded = threaded,
            .allocator = allocator,
            ._log = log,
            .options = options,
        };
    }

    pub fn deinit(self: *Runner) void {
        self._log.close(self._threaded.io());
        self._threaded.deinit();
    }

    fn logCommand(self: *Runner, io: std.Io, argv: []const []const u8) ExecError!bool {
        const joined = try std.mem.join(self.allocator, " ", argv);
        defer self.allocator.free(joined);

        std.debug.print("$ {s}\n", .{joined});
        if (self.options.dry_run) return false;

        var buffer: [4096]u8 = undefined;
        var log_writer = self._log.writerStreaming(io, &buffer);
        try log_writer.interface.print("$ {s}\n", .{joined});
        try log_writer.interface.flush();
        return true;
    }

    fn checkTerm(
        self: *Runner,
        term: Child.Term,
        argv: []const []const u8,
    ) ExecError!void {
        switch (term) {
            .exited => |code| if (code != 0) {
                const joined = std.mem.join(self.allocator, " ", argv) catch "";
                defer if (joined.len != 0) self.allocator.free(joined);
                std.debug.print("command failed (exit {d}): {s}\n check log: {s}\n", .{ code, joined, self.options.log_file_path });
                return error.CommandFailed;
            },
            else => {
                std.debug.print("command terminated abnormally\n check log: {s}\n", .{self.options.log_file_path});
                return error.CommandFailed;
            },
        }
    }

    pub fn exec(self: *Runner, argv: []const []const u8) ExecError!void {
        const io = self._threaded.io();
        if (!try self.logCommand(io, argv)) return;

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .stdout = .{ .file = self._log },
            .stderr = .{ .file = self._log },
        });

        try self.checkTerm(try child.wait(io), argv);
    }

    pub fn execInput(self: *Runner, argv: []const []const u8, input: []const u8) ExecError!void {
        const io = self._threaded.io();
        if (!try self.logCommand(io, argv)) return;

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .stdin = .pipe,
            .stdout = .{ .file = self._log },
            .stderr = .{ .file = self._log },
        });

        var buf: [4096]u8 = undefined;

        var w = child.stdin.?.writerStreaming(io, &buf);
        try w.interface.writeAll(input);
        try w.interface.flush();

        child.stdin.?.close(io);
        child.stdin = null;

        try self.checkTerm(try child.wait(io), argv);
    }

    pub fn execRead(self: *Runner, allocator: std.mem.Allocator, argv: []const []const u8) ExecError![]u8 {
        const io = self._threaded.io();
        if (!try self.logCommand(io, argv)) return try allocator.dupe(u8, "");

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .stdout = .pipe,
            .stderr = .{ .file = self._log },
        });

        var read_buffer: [4096]u8 = undefined;
        var stdout_reader = child.stdout.?.readerStreaming(io, &read_buffer);

        var sink: std.Io.Writer.Allocating = .init(allocator);
        defer sink.deinit();

        _ = try stdout_reader.interface.streamRemaining(&sink.writer);

        try self.checkTerm(try child.wait(io), argv);
        return try sink.toOwnedSlice();
    }

    pub fn execChroot(self: *Runner, argv: []const []const u8) ExecError!void {
        var chroot: std.ArrayList([]const u8) = try .initCapacity(self.allocator, argv.len + 2);
        defer chroot.deinit(self.allocator);

        chroot.appendSliceAssumeCapacity(&.{ "artix-chroot", "/mnt" });
        chroot.appendSliceAssumeCapacity(argv);

        try self.exec(chroot.items);
    }

    pub fn writeFile(self: *Runner, path: []const u8, contents: []const u8) !void {
        const io = self._threaded.io();

        if (!try self.logCommand(io, &.{ "write", path })) return;

        if (std.fs.path.dirname(path)) |dir|
            try std.Io.Dir.cwd().createDirPath(io, dir);

        const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var writer = file.writerStreaming(io, &buffer);
        try writer.interface.writeAll(contents);
        try writer.interface.flush();
    }
};
