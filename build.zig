const std = @import("std");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_step = b.addWriteFiles();

    const embedded_payload = genManifest(b, gen_step, "./src/core") catch |err| {
        std.debug.print("failed to generate manifest: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const embedded_core_file = gen_step.add("embedded_core.zig", embedded_payload);

    const exe = b.addExecutable(.{
        .name = "vektor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    exe.root_module.addAnonymousImport("embedded_core", .{
        .root_source_file = embedded_core_file,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn shouldSkip(path: []const u8) bool {
    const skip_dirs = [_][]const u8{ ".zig-cache", ".git", "zig-out", "profile.zig" };

    for (skip_dirs) |dir| {
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
