const std = @import("std");

pub const emit = @import("emit.zig");
pub const ziggen = @import("ziggen.zig");

pub const GlobalState = struct {
    io: std.Io,
};

var state: ?GlobalState = null;

pub fn init(gs: GlobalState) void {
    state = gs;
}

fn get() *GlobalState {
    return &(state orelse @panic("root.init() not called"));
}

pub fn io() std.Io {
    return get().io;
}
