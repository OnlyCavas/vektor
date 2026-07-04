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
        const gpu_pkgs: []const []const u8 = switch (self.cfg.gpu) {
            .intel => &.{ "mesa", "vulkan-intel", "intel-media-driver" },
            .amd => &.{ "mesa", "vulkan-radeon", "libva-mesa-driver" },
            .nvidia => &.{ "nvidia-open-dkms", "nvidia-utils", "dkms" },
        };

        const microcode = switch (self.cfg.cpu) {
            .intel => "intel-ucode",
            .amd => "amd-ucode",
        };

        return .{ .base = &[_][]const u8{microcode} ++ gpu_pkgs };
    }

    pub fn install(_: Hardware, _: *const Ctx) !void {}
};
