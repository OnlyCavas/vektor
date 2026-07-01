const config = @import("config");

const PackageSpec = config.PackageSpec;
const Ctx = @import("../lib.zig").Context;

pub const PrivelidgeEscalation = struct {
    pub fn init() PrivelidgeEscalation {
        return .{};
    }

    pub fn spec(self: PrivelidgeEscalation) PackageSpec {
        return switch (self.cfg) {
            // sudo
            // doas
        };
    }

    pub fn install(self: PrivelidgeEscalation, ctx: *const Ctx) !void {
        _ = self;
        _ = ctx;

        // switch (self.cfg) {}
    }
};
