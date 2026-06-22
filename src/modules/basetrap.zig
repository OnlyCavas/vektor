const std = @import("std");

const Runner = @import("utils").Runner;
const InstallConfig = @import("config").InstallConfig;

pub const label = "Basetrap";

pub fn run(runner: *Runner, _: InstallConfig) !void {
    try runner.exec(&.{ "ls", "-lha" });
}
