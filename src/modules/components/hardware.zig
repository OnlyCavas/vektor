const config = @import("config");

const HardwareConfig = config.HardwareConfig;
const PackageSpec = config.PackageSpec;
const InstallConfig = config.InstallConfig;

const Ctx = @import("../lib.zig").Context;

pub const Hardware = struct {
    cfg: HardwareConfig,

    pub fn fromConfig(cfg: *const InstallConfig) Hardware {
        return .{ .cfg = cfg.hardware };
    }

    pub fn spec(self: Hardware) PackageSpec {
        return .{ .base = &[_][]const u8{self.cfg.cpu.ucode()} ++ self.cfg.gpu.packages() };
    }

    pub fn install(self: Hardware, ctx: *const Ctx) !void {
        _ = self;
        _ = ctx;
    }
};
