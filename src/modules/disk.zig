const std = @import("std");

const Runner = @import("utils").Runner;
const InstallConfig = @import("config").InstallConfig;

pub const label = "Partition disk...";

pub fn run(runner: *Runner, _: InstallConfig) !void {
    try runner.exec(&.{ "echo", "disk partition" });
}
