const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config = b.createModule(.{
        .root_source_file = b.path("config.zig"),
    });

    const installationProfile = b.createModule(.{
        .root_source_file = b.path("profile.zig"),
        .imports = &.{
            .{ .name = "vektor-installation", .module = config },
        },
    });

    const runner = b.createModule(.{
        .root_source_file = b.path("cwd-runner.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "vektor-install",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config_types", .module = config },
                .{ .name = "config", .module = installationProfile },
                .{ .name = "cwd", .module = runner },
            },
        }),
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
