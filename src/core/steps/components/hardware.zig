const config_types = @import("config_types");

const HardwareConfig = config_types.HardwareConfig;
const PackageSpec = config_types.PackageSpec;
const InstallConfig = config_types.InstallConfig;

const Ctx = @import("../context.zig").Context;

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
            .virtual => &.{"mesa"},
        };

        const microcode = switch (self.cfg.cpu) {
            .intel => "intel-ucode",
            .amd => "amd-ucode",
        };

        return .{ .base = &[_][]const u8{microcode} ++ gpu_pkgs };
    }

    pub fn install(_: Hardware, _: *const Ctx) !void {}
};
