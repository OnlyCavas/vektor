const std = @import("std");
const builtin = @import("builtin");
const buildpkg = @import("src/build/main.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.addModule("vektor", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "vektor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vektor", .module = root_mod },
            },
        }),
    });

    const cli = try buildpkg.Cli.init(b, root_mod);
    try cli.addImport(exe);

    const embedded_core = try buildpkg.EmbeddedCore.init(b);
    try embedded_core.addImport(exe);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
