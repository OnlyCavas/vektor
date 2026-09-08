const std = @import("std");
const config_types = @import("config_types");

const meta = @import("std").meta;

const Runner = @import("cwd").Runner;

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

pub const Services = struct {
    runner: *Runner,
    init: InitSystem,

    pub fn initUserDir(self: Services, allocator: std.mem.Allocator, username: []const u8) !?[]const u8 {
        return switch (self.init) {
            .dinit => try std.fmt.allocPrint(allocator, "/home/{s}/.config/dinit.d", .{username}),
            .runit => try std.fmt.allocPrint(allocator, "/home/{s}/.runit/sv", .{username}),
            else => null,
        };
    }

    pub fn ensureInitConfig(self: Services, allocator: std.mem.Allocator, username: []const u8) !void {
        const baseDir = (try self.initUserDir(allocator, username)) orelse return;
        defer allocator.free(baseDir);

        switch (self.init) {
            .dinit => {
                const bootd = try std.fmt.allocPrint(allocator, "{s}/boot.d", .{baseDir});
                defer allocator.free(bootd);

                const owner = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ username, username });
                defer allocator.free(owner);

                try self.runner.execChroot(allocator, &.{ "mkdir", "-p", bootd });
            },
            .runit => {
                try self.runner.execChroot(allocator, &.{ "mkdir", "-p", baseDir });
            },
            else => {},
        }
    }

    pub fn chownInitConfig(self: Services, allocator: std.mem.Allocator, username: []const u8) !void {
        return switch (self.init) {
            .dinit, .runit => {
                const homeDir = try std.fmt.allocPrint(allocator, "/home/{s}/.config", .{username});
                defer allocator.free(homeDir);

                const owner = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ username, username });
                defer allocator.free(owner);

                try self.runner.execChroot(allocator, &.{ "chown", "-R", owner, homeDir });
            },
            else => {},
        };
    }

    pub fn enableService(self: Services, allocator: Allocator, service: ServiceSpec, user: []const u8) !void {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();

        const arean_alloc = arena.allocator();
        const serviceName = service.service();

        switch (self.init) {
            .runit => {
                const runitBaseDir = "/etc/runit/sv";
                const target = try std.fmt.allocPrint(arean_alloc, "{s}/{s}", .{
                    runitBaseDir,
                    serviceName,
                });

                switch (service.scope) {
                    .boot => {
                        try self.runner.execChroot(arean_alloc, &.{ "ln", "-sf", target, "/etc/runit/runsvdir/default/" });
                    },
                    .user => {
                        const baseDir = (try self.initUserDir(arean_alloc, user)) orelse return;
                        try self.runner.execChroot(arean_alloc, &.{ "ln", "-sf", target, baseDir });
                    },
                }
            },
            .dinit => {
                const dinitBase = "/etc/dinit.d";

                switch (service.scope) {
                    .boot => {
                        const target = try std.fmt.allocPrint(arean_alloc, "{s}/{s}", .{
                            dinitBase,
                            serviceName,
                        });

                        const link = try std.fmt.allocPrint(arean_alloc, "{s}/boot.d", .{
                            dinitBase,
                        });

                        try self.runner.execChroot(arean_alloc, &.{ "ln", "-sf", target, link });
                    },
                    .user => {
                        const target = try std.fmt.allocPrint(arean_alloc, "{s}/user/{s}", .{
                            dinitBase,
                            serviceName,
                        });

                        const baseDir = (try self.initUserDir(arean_alloc, user)) orelse return;

                        const userBaseDir = try std.fmt.allocPrint(
                            arean_alloc,
                            "{s}/boot.d",
                            .{baseDir},
                        );

                        try self.runner.execChroot(arean_alloc, &.{ "ln", "-sf", target, userBaseDir });
                    },
                }
            },
            else => {},
        }
    }

    pub fn start(self: Services, allocator: Allocator, service: []const u8) !void {
        switch (self.init) {
            .openrc => try self.runner.exec(allocator, &.{ "rc-service", service, "start" }),
            .runit => try self.runner.exec(allocator, &.{ "sv", "up", service }),
            .dinit => try self.runner.exec(allocator, &.{ "dinitctl", "start", service }),
            .s6 => try self.runner.exec(allocator, &.{ "s6-rc", "-u", "change", service }),
        }
    }
};

pub const Context = struct {
    allocator: Allocator,
    runner: *Runner,
    cfg: *const InstallConfig,
    packages: []const []const u8,

    pub fn services(self: *const Context) Services {
        return .{ .runner = self.runner, .init = self.cfg.packages.initSystem };
    }
};

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
