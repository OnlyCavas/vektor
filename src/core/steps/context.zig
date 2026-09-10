const std = @import("std");
const cwd = @import("cwd");
const config_types = @import("config_types");

const Runner = cwd.Runner;
const Allocator = std.mem.Allocator;

const InitSystem = config_types.InitSystem;
const PackageSpec = config_types.PackageSpec;
const ServiceSpec = config_types.ServiceSpec;
const InstallConfig = config_types.InstallConfig;

pub const Context = struct {
    allocator: Allocator,
    runner: *Runner,
    cfg: *const InstallConfig,
    packages: []const []const u8,

    pub fn services(self: *const Context) Services {
        return .{ .runner = self.runner, .init = self.cfg.packages.initSystem };
    }
};

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
