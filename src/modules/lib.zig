const std = @import("std");
const config = @import("config");

const meta = @import("std").meta;

const Runner = @import("utils").Runner;
const InstallConfig = config.InstallConfig;
const InitSystem = config.InitSystem;
const PackageSpec = config.PackageSpec;

pub const Services = struct {
    runner: *Runner,
    init: InitSystem,

    pub fn enable(self: Services, service: []const u8) !void {
        const allocator = self.runner.allocator;

        switch (self.init) {
            .openrc => try self.runner.execChroot(&.{ "rc-update", "add", service, "default" }),
            .runit => {
                const target = try std.fmt.allocPrint(allocator, "/etc/runit/sv/{s}", .{service});
                defer allocator.free(target);

                try self.runner.execChroot(&.{ "ln", "-sf", target, "/etc/runit/runsvdir/default/" });
            },
            .dinit => {
                const target = try std.fmt.allocPrint(allocator, "/etc/dinit.d/{s}", .{service});
                defer allocator.free(target);

                const link = try std.fmt.allocPrint(allocator, "/etc/dinit.d/boot.d/{s}", .{service});
                defer allocator.free(link);

                try self.runner.execChroot(&.{ "ln", "-sf", target, link });
            },
            .s6 => {
                const marker = try std.fmt.allocPrint(allocator, "/etc/s6/adminsv/default/contents.d/{s}", .{service});
                defer allocator.free(marker);

                try self.runner.execChroot(&.{ "touch", marker });
                try self.runner.execChroot(&.{"s6-db-reload"});
            },
        }
    }

    pub fn start(self: Services, service: []const u8) !void {
        switch (self.init) {
            .openrc => try self.runner.exec(&.{ "rc-service", service, "start" }),
            .runit => try self.runner.exec(&.{ "sv", "up", service }),
            .dinit => try self.runner.exec(&.{ "dinitctl", "start", service }),
            .s6 => try self.runner.exec(&.{ "s6-rc", "-u", "change", service }),
        }
    }
};

pub const Context = struct {
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

const disk = @import("disk.zig");
const install = @import("install.zig");
const extra = @import("extra.zig");

const modules = .{
    disk,
    install,
    extra,
};

comptime {
    for (modules) |m| Module.verify(m);
}

pub fn runAll(runner: *Runner, comptime cfg: InstallConfig) !void {
    const shellSpec = comptime blk: {
        var base: []const []const u8 = &.{};

        for (cfg.system.users) |user| {
            base = base ++ &[_][]const u8{user.shell.getPackageName()};
        }

        break :blk PackageSpec{ .base = base };
    };

    const specs = comptime PackageSpec.merge(
        collectSpecs(modules, cfg) ++ &[_]PackageSpec{shellSpec},
    );

    const installPackages = comptime specs.packageList();

    var ctx: Context = .{
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

    for (specs.services) |services| {
        try ctx.services().enable(services);
    }
}
