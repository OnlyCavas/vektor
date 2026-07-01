const config = @import("config");
const Ctx = @import("lib.zig").Context;

pub const label = "Hardeneding System";

pub const installPackages: config.PackageSpec = .{
    .base = &.{ "linux-hardnend", "linux-headers" },
    .services = &.{},
};

pub const installComponents = .{
    // firewall module
    // nvidia driver module
    // crypto disk module
};

pub fn run(ctx: *const Ctx) !void {
    _ = ctx;
}
