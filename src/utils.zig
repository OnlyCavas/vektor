const std = @import("std");

pub const ExecError = error{
    CommandFailed,
} || std.mem.Allocator.Error || std.process.SpawnError || std.Io.Writer.Error;

pub const RunnerOptions = struct {
    dry_run: bool = false,
    log_file_path: []const u8 = "/var/log/artix-installer.log",
};

pub const Runner = struct {
    _threaded: std.Io.Threaded,
    _allocator: std.mem.Allocator,
    _log: std.Io.File,
    options: RunnerOptions,

    pub fn init(allocator: std.mem.Allocator, options: RunnerOptions) !Runner {
        var threaded: std.Io.Threaded = .init(allocator, .{});

        const log = try std.Io.Dir.createFileAbsolute(
            threaded.io(),
            options.log_file_path,
            .{},
        );

        return .{
            ._threaded = threaded,
            ._allocator = allocator,
            ._log = log,
            .options = options,
        };
    }

    pub fn deinit(self: *Runner) void {
        self._log.close(self._threaded.io());
        self._threaded.deinit();
    }

    pub fn exec(self: *Runner, argv: []const []const u8) ExecError!void {
        const io = self._threaded.io();
        const exec_fmt = "$ {s} \n";

        const joined = try std.mem.join(self._allocator, " ", argv);
        defer self._allocator.free(joined);

        std.debug.print(exec_fmt, .{joined});
        if (self.options.dry_run) return;

        var buffer: [4096]u8 = undefined;

        var log_writer = self._log.writerStreaming(io, &buffer);
        try log_writer.interface.print(exec_fmt, .{joined});
        try log_writer.interface.flush();

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .stdout = .{ .file = self._log },
            .stderr = .{ .file = self._log },
        });

        const term = try child.wait(io);

        switch (term) {
            .exited => |code| if (code != 0) {
                std.debug.print(
                    "command failed (exit {d}): {s}\n check log: {s} for more detail\n",
                    .{ code, joined, self.options.log_file_path },
                );

                return ExecError.CommandFailed;
            },
            else => {
                std.debug.print(
                    "command terminated abnormally: {s}\n check log: {s} for more detail\n",
                    .{ joined, self.options.log_file_path },
                );

                return ExecError.CommandFailed;
            },
        }
    }

    pub fn execChroot(self: *Runner, argv: []const []const u8) ExecError!void {
        var chroot: std.ArrayList([]const u8) = try .initCapacity(self._allocator, argv.len + 2);
        defer chroot.deinit(self._allocator);

        chroot.appendSliceAssumeCapacity(&.{ "artix-chroot", "/mnt" });
        chroot.appendSliceAssumeCapacity(argv);

        try self.exec(chroot.items);
    }
};
