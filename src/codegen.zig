const std = @import("std");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

pub const ZigValue = union(enum) {
    string: []const u8,
    enum_literal: []const u8,
    integer: i64,
    boolean: bool,
    array: []const ZigValue,
    strct: []const Field,
    nil: void,

    pub const Field = struct { key: []const u8, value: ZigValue };
};

fn isValidZigIdentifier(identifier: []const u8) bool {
    if (identifier.len == 0) return false;

    if (!std.ascii.isAlphabetic(identifier[0]) and identifier[0] != '_') return false;

    for (identifier[1..]) |id| {
        if (!std.ascii.isAlphanumeric(id) and id != '_') return false;
    }

    return std.zig.Token.getKeyword(identifier) == null;
}

fn writeFieldName(fieldName: []const u8, writer: *Writer) !void {
    if (isValidZigIdentifier(fieldName)) {
        try writer.writeAll(fieldName);
    } else {
        try writer.writeAll("@\"");
        try writer.writeAll(fieldName);
        try writer.writeAll("\"");
    }
}

fn writeEscapedString(value: []const u8, writer: *Writer) !void {
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...8, 11, 12, 14...31 => try writer.print("\\x{x:0>2}", .{c}),
            else => try writer.writeByte(c),
        }
    }
}

pub fn writeZigValue(zv: ZigValue, writer: *Writer) !void {
    switch (zv) {
        .string => |value| {
            try writer.writeAll("\"");
            try writeEscapedString(value, writer);
            try writer.writeAll("\"");
        },
        .enum_literal => |literal| {
            try writer.writeByte('.');
            try writeFieldName(literal, writer);
        },
        .integer => |value| try writer.print("{d}", .{value}),
        .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
        .array => |items| {
            try writer.writeAll("&.{");

            for (items) |i| {
                try writeZigValue(i, writer);
                try writer.writeByte(',');
            }

            try writer.writeByte('}');
        },
        .strct => |fields| {
            try writer.writeAll(".{");

            for (fields) |f| {
                try writer.writeByte('.');
                try writeFieldName(f.key, writer);
                try writer.writeByte('=');
                try writeZigValue(f.value, writer);
                try writer.writeByte(',');
            }

            try writer.writeByte('}');
        },
        .nil => try writer.writeAll("null"),
    }
}

pub const ZigCode = struct {
    source: []const u8,

    pub const CodegenError = error{
        InvalidGeneratedSyntax,
    } || std.mem.Allocator.Error || std.Io.Writer.Error;

    pub fn deinit(self: ZigCode, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
    }

    pub fn fmt(
        allocator: Allocator,
        raw_src: []const u8,
    ) CodegenError!ZigCode {
        var wAlloc: Writer.Allocating = .init(allocator);
        defer wAlloc.deinit();

        const source_z = try allocator.dupeZ(u8, raw_src);
        defer allocator.free(source_z);

        var astree: std.zig.Ast = try .parse(allocator, source_z, .zig);
        defer astree.deinit(allocator);

        if (astree.errors.len != 0) {
            std.log.err("codegen produced {d} sintax errors", .{astree.errors.len});
            return CodegenError.InvalidGeneratedSyntax;
        }

        try astree.render(allocator, &wAlloc.writer, .{});
        return .{ .source = try wAlloc.toOwnedSlice() };
    }
};
