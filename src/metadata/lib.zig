const std = @import("std");

const NFTablesConfig = @import("config").firewall.NFTables;

pub fn makeNFTConfigFile(cfg: NFTablesConfig, allocator: std.mem.Allocator) ![]const u8 {
    var allocWriter: std.Io.Writer.Allocating = .init(allocator);
    defer allocWriter.deinit();
    const writer = &allocWriter.writer;

    try writer.writeAll("#!/usr/sbin/nft -f\nflush ruleset\ntable inet filter {\n");

    for (cfg.lanCluster) |cluster| {
        try writer.print("\tset {s} {{\n\t\ttype ipv4_addr\n\t\tflags interval\n\t\telements = {{ ", .{cluster.label});
        for (cluster.maskList, 0..) |mask, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(mask);
        }
        try writer.writeAll(" }\n\t}\n");
    }

    try writer.writeAll(
        "\tchain input {\n" ++
            "\t\ttype filter hook input priority 0; policy drop;\n" ++
            "\t\tiif \"lo\" accept\n" ++
            "\t\tct state established,related accept\n" ++
            "\t\tct state invalid drop\n" ++
            "\t\tip protocol icmp icmp type { destination-unreachable, time-exceeded } accept\n" ++
            "\t\tip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, destination-unreachable, packet-too-big, time-exceeded } accept\n",
    );

    for (cfg.input.rules) |rule| {
        try writer.writeAll("\t\t");

        if (rule.clusterLabel) |label| try writer.print("ip saddr @{s} ", .{label});

        if (rule.protocol) |protocol| try writer.print("{s} ", .{@tagName(protocol)});

        if (rule.dport) |dport| try writer.print("dport {s} ", .{dport});

        if (rule.sport) |sport| try writer.print("sport {s} ", .{sport});

        if (rule.extend) |extend| try writer.print("{s} ", .{extend});

        try writer.print("{s}\n", .{rule.policy.getName()});
    }

    try writer.writeAll(
        "\t\treject with icmpx type port-unreachable\n" ++
            "\t}\n" ++
            "\tchain forward {\n" ++
            "\t\ttype filter hook forward priority 0; policy drop;\n" ++
            "\t}\n" ++
            "\tchain output {\n" ++
            "\t\ttype filter hook output priority 0; policy accept;\n" ++
            "\t}\n" ++
            "}\n",
    );

    return try allocWriter.toOwnedSlice();
}
