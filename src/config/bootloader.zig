pub const KernelEntry = struct {
    label: []const u8,
    package: enum {
        standard,
        lts,
        hardened,

        pub fn name(self: @This()) []const u8 {
            return switch (self) {
                .standard => "linux",
                .lts => "linux-lts",
                .hardened => "linux-hardened",
            };
        }
    },
};

pub const LimineConfig = struct {
    timeout: u32 = 5,
    withWindows: ?struct { label: []const u8 } = null,
    bootEntryName: []const u8 = "Artix Limine",
    entries: []const KernelEntry = &.{
        .{
            .label = "Artix Linux",
            .package = .standard,
        },
    },

    pub const default: LimineConfig = .{};
};

pub const BootLoaderConfig = union(enum) {
    limine: LimineConfig,

    pub const default: BootLoaderConfig = .{ .limine = .default };
};
