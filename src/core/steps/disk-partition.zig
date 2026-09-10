const std = @import("std");
const context = @import("context.zig");
const config_types = @import("config_types");

const DiskConfig = config_types.DiskConfig;

const Ctx = context.Context;
const Runner = @import("cwd").Runner;

pub const label = "Partition the disks";

pub fn run(ctx: *const Ctx) !void {
    var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try partition(ctx.runner, allocator, ctx.cfg.disk);
    try format(ctx.runner, allocator, ctx.cfg.disk);
    try mount(ctx.runner, allocator, ctx.cfg.disk);
}

fn partition(ctx: *Runner, allocator: std.mem.Allocator, disk: DiskConfig) !void {
    var script: std.ArrayList(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, try std.fmt.allocPrint(
        allocator,
        "label: {s}\n",
        .{disk.getTableName()},
    ));

    for (disk.partitions) |part| {
        const size: []const u8 = switch (part.size) {
            .gib => |g| try std.fmt.allocPrint(allocator, "{d}G", .{g}),
            .mib => |m| try std.fmt.allocPrint(allocator, "{d}M", .{m}),
            .remaining => "",
        };

        const sfdiskType: []const u8 = switch (part.fs) {
            .swap => "S",
            .fat32 => "U",
            .ext4 => "L",
        };

        try script.appendSlice(allocator, try std.fmt.allocPrint(allocator, ",{s},{s}\n", .{ size, sfdiskType }));
    }

    try ctx.execInput(allocator, &.{ "sfdisk", "--wipe", "always", disk.device }, script.items);
}

fn partIndex(disk: DiskConfig, plabel: []const u8) ?usize {
    for (disk.partitions, 1..) |part, idx|
        if (std.mem.eql(u8, part.label, plabel)) return idx;

    return null;
}

fn format(ctx: *Runner, allocator: std.mem.Allocator, disk: DiskConfig) !void {
    for (disk.partitions, 1..) |part, index| {
        const device = try disk.partDevice(allocator, index);

        switch (part.fs) {
            .ext4 => try ctx.exec(allocator, &.{ "mkfs.ext4", "-F", device }),
            .fat32 => try ctx.exec(allocator, &.{ "mkfs.fat", "-F32", device }),
            .swap => {
                try ctx.exec(allocator, &.{ "mkswap", device });
                try ctx.exec(allocator, &.{ "swapon", device });
            },
        }
    }
}

fn mount(ctx: *Runner, allocator: std.mem.Allocator, disk: DiskConfig) !void {
    for (disk.mounts) |m| {
        const index = partIndex(disk, m.partition) orelse return error.UnknownPartition;
        const device = try disk.partDevice(allocator, index);
        const target = try std.fmt.allocPrint(allocator, "/mnt{s}", .{m.target});

        try ctx.exec(allocator, &.{ "mount", "--mkdir", device, target });
    }
}
