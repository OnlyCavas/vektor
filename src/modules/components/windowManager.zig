const std = @import("std");
const config = @import("config");

const PackageSpec = config.PackageSpec;
const ServiceSpec = config.ServiceSpec;
const InstallConfig = config.InstallConfig;
const DesktopConfig = config.DesktopConfig;

const Ctx = @import("../lib.zig").Context;
const Runner = @import("utils").Runner;

pub const WindowManager = struct {
    cfg: DesktopConfig,

    pub fn fromConfig(cfg: *const InstallConfig) WindowManager {
        return .{ .cfg = cfg.desktop };
    }

    pub fn spec(self: WindowManager) PackageSpec {
        comptime var packages: []const []const u8 = &.{};
        comptime var services: []const ServiceSpec = &.{};

        switch (self.cfg.windowManager) {
            .niri => packages = packages ++ .{
                "niri",
                "xwayland-satellite",
            },
            .hyprland => packages = packages ++ .{
                "hyprland",
                "xorg-xwayland",
            },
        }

        for (self.cfg.desktopPortal) |portal| {
            packages = packages ++ .{switch (portal) {
                .cosmic => "xdg-desktop-portal-cosmic",
                .wlr => "xdg-desktop-portal-wlr",
                .hyprland => "xdg-desktop-portal-hyprland",
                .gnome => "xdg-desktop-portal-gnome",
                .gtk => "xdg-desktop-portal-gtk",
            }};
        }

        packages = packages ++ .{"xdg-desktop-portal"};

        switch (self.cfg.audio) {
            .pipewire => {
                packages = packages ++ .{
                    "pipewire",
                    "pipewire-alsa",
                    "pipewire-jack",
                    "rtkit",
                };

                services = services ++ [_]ServiceSpec{
                    .{ .pkg = "pipewire-pulse", .scope = .user },
                    .{ .pkg = "wireplumber", .scope = .user },
                };
            },
            .pulseaudio => packages = packages ++ .{
                "pulseaudio",
                "pulseaudio-alsa",
            },
            .none => {},
        }

        return .{
            .base = packages,
            .services = services,
        };
    }

    pub fn install(self: WindowManager, ctx: *const Ctx) !void {
        const runner = ctx.runner;
        const cfg = self.cfg;

        var arena: std.heap.ArenaAllocator = .init(ctx.runner.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        try configureDesktopPortal(runner, cfg, allocator);
        // try configureSound(runner, cfg, allocator);
    }

    fn configureDesktopPortal(runner: *Runner, cfg: DesktopConfig, allocator: std.mem.Allocator) !void {
        var allocWriter: std.Io.Writer.Allocating = .init(allocator);
        defer allocWriter.deinit();
        const writer = &allocWriter.writer;

        try writer.print(
            \\[preferred]
            \\default=cosmic
            \\org.freedesktop.impl.portal.FileChooser=cosmic
            \\org.freedesktop.impl.portal.ScreenCast=wlr
            \\org.freedesktop.impl.portal.Screenshot=wlr
        , .{});

        const configPath = try std.fmt.allocPrint(
            allocator,
            "/mnt/etc/xdg/xdg-desktop-portal/{s}-portals.conf",
            .{cfg.windowManager.getName()},
        );

        defer allocator.free(configPath);

        try runner.writeFile(configPath, try allocWriter.toOwnedSlice());
    }

    // fn configureSound(runner: *Runner, cfg: DesktopConfig, allocator: std.mem.Allocator) !void {}
};
