const EmbeddedCore = @This();

const std = @import("std");
const Writer = std.Io.Writer;

output: std.Build.LazyPath,

pub fn init(b: *std.Build) !EmbeddedCore {
    const wfs = b.addWriteFiles();

    const embedded_payload = genManifest(b, wfs, "./src/core") catch |err| {
        std.debug.print("failed to generate manifest: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const embedded_core_file = wfs.add("embedded_core.zig", embedded_payload);

    return .{ .output = embedded_core_file };
}

pub fn addImport(self: *const EmbeddedCore, step: *std.Build.Step.Compile) !void {
    step.root_module.addAnonymousImport("embedded_core", .{
        .root_source_file = self.output,
    });
}

fn shouldSkip(path: []const u8) bool {
    const skip_dirs = [_][]const u8{ ".zig-cache", ".git", "zig-out", "profile.zig" };

    inline for (skip_dirs) |dir| {
        if (std.mem.indexOf(u8, path, dir) != null) return true;
    }

    return false;
}

fn genManifest(b: *std.Build, gen_step: *std.Build.Step.WriteFile, core_dir: []const u8) ![]const u8 {
    const allocator = b.allocator;

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const io = threaded.io();

    var wAlloc: Writer.Allocating = .init(allocator);
    defer wAlloc.deinit();

    try wAlloc.writer.writeAll(
        \\pub const EmbeddedFile = struct { rel_path: []const u8, payload: []const u8 };
        \\
        \\pub const files = [_]EmbeddedFile{
        \\
    );

    const cwd = std.Io.Dir.cwd();

    const core = try cwd.openDir(io, core_dir, .{ .iterate = true });
    defer core.close(io);
    var walker = try core.walk(allocator);

    while (try walker.next(io)) |item| {
        if (item.kind != .file) continue;
        if (!std.mem.endsWith(u8, item.path, ".zig")) continue;
        if (shouldSkip(item.path)) continue;

        const src_path = try std.fs.path.join(b.allocator, &.{ core_dir, item.path });
        _ = gen_step.addCopyFile(b.path(src_path), item.path);

        try wAlloc.writer.print(
            "    .{{ .rel_path = \"{s}\", .payload = @embedFile(\"{s}\") }},\n",
            .{ item.path, item.path },
        );
    }

    try wAlloc.writer.writeAll("};\n");

    return wAlloc.toOwnedSlice();
}
