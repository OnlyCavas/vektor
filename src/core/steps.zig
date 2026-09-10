const std = @import("std");
const config_types = @import("config_types");
const context = @import("steps/context.zig");

const meta = @import("std").meta;

const Runner = @import("cwd").Runner;

const Context = context.Context;
const InstallConfig = config_types.InstallConfig;
const InitSystem = config_types.InitSystem;
const PackageSpec = config_types.PackageSpec;
const ServiceSpec = config_types.ServiceSpec;

const Allocator = std.mem.Allocator;

const disk = @import("steps/disk-partition.zig");
const system_install = @import("steps/system-install.zig");
const extra = @import("steps/extra-config.zig");

const modules = .{
    disk,
    system_install,
    extra,
};

comptime {
    for (modules) |m| Module.verify(m);
}

const Module = struct {
    pub fn hasPackages(comptime M: type) bool {
        return @hasDecl(M, "installPackages") and @TypeOf(M.installPackages) == PackageSpec;
    }

    pub fn hasComponents(comptime M: type) bool {
        return @hasDecl(M, "installComponents");
    }

    pub fn verify(comptime M: type) void {
        if (!meta.hasFn(M, "run")) {
            @compileError(name(M) ++ " must declare `pub fn run(*Runner, InstallConfig) !void`");
        }

        if (!@hasDecl(M, "label")) {
            @compileError(name(M) ++ " declare `pub const label: []const u8`");
        }

        if (@hasDecl(M, "installPackages") and @TypeOf(M.installPackages) != PackageSpec)
            @compileError(name(M) ++ ": `installPackages` must be a PackageSpec");
    }

    fn name(comptime M: type) []const u8 {
        return "module '" ++ @typeName(M) ++ "'";
    }
};

fn collectSpecs(
    comptime mods: anytype,
    comptime cfg: InstallConfig,
) []const PackageSpec {
    var specs: []const PackageSpec = &.{};

    inline for (mods) |mod| {
        if (Module.hasPackages(mod)) {
            specs = specs ++ &[_]PackageSpec{mod.installPackages};
        }

        if (Module.hasComponents(mod)) {
            inline for (mod.installComponents) |component|
                specs = specs ++ &[_]PackageSpec{component.fromConfig(&cfg).spec()};
        }
    }

    return specs ++ &[_]PackageSpec{cfg.packages};
}

fn installComponents(comptime M: type, ctx: *const Context) !void {
    inline for (M.installComponents) |component|
        try component.fromConfig(ctx.cfg).install(ctx);
}

fn enableServices(ctx: *const Context, specs: PackageSpec, username: []const u8) !void {
    try ctx.services().ensureInitConfig(ctx.allocator, username);

    for (specs.services) |service|
        try ctx.services().enableService(ctx.allocator, service, username);

    try ctx.services().chownInitConfig(ctx.allocator, username);
}

pub fn install(allocator: Allocator, runner: *Runner, comptime cfg: InstallConfig) !void {
    const shellSpec = comptime blk: {
        var base: []const []const u8 = &.{};

        for (cfg.system.users) |user| {
            base = base ++ &[_][]const u8{user.shell.getPackageName()};
        }

        break :blk PackageSpec{
            .base = base,
            .initSystem = cfg.packages.initSystem,
        };
    };

    const specs = comptime PackageSpec.merge(
        collectSpecs(modules, cfg) ++ &[_]PackageSpec{shellSpec},
    );

    const installPackages = comptime specs.packageList();

    var ctx: Context = .{
        .allocator = allocator,
        .runner = runner,
        .cfg = &cfg,
        .packages = installPackages,
    };

    inline for (modules) |m| {
        m.run(&ctx) catch |err| {
            std.debug.print("step: {s} failed\n", .{m.label});
            return err;
        };

        if (@hasDecl(m, "installComponents")) try installComponents(m, &ctx);
    }

    const primary = try cfg.system.primaryUser();
    try enableServices(&ctx, specs, primary.name);

    try runner.exec(allocator, &.{"sync"});
    try runner.exec(allocator, &.{ "umount", "-R", "/mnt" });
    try runner.exec(allocator, &.{"reboot"});
}
