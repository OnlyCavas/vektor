const std = @import("std");

pub fn build(b: *std.Build) void {
    const profile = b.option([]const u8, "profile", "machine config profile") orelse "default";
    const configPath = b.fmt("profiles/{s}.zig", .{profile});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config_types_mod = b.createModule(.{
        .root_source_file = b.path("src/config/lib.zig"),
    });

    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils.zig"),
    });

    const metadata = b.createModule(.{
        .root_source_file = b.path("src/metadata/lib.zig"),
    });

    const lib = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .imports = &.{
            .{ .name = "config", .module = config_types_mod },
            .{ .name = "utils", .module = utils },
            .{ .name = "metadata", .module = metadata },
        },
    });

    const config_mod = b.createModule(.{
        .root_source_file = b.path(configPath),
        .imports = &.{
            .{ .name = "artix-installer", .module = config_types_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "artix_installer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_mod },
                .{ .name = "lib", .module = lib },
                .{ .name = "utils", .module = utils },
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
