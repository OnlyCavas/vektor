const std = @import("std");

// placeholder generated cli import
const cli = @import("cli.zig");

pub const ArgsIterator = std.process.Args.Iterator;

const Action = cli.Action;
const Allocator = std.mem.Allocator;

pub const Parser = struct {
    argIterator: ArgsIterator,
    peeked: ?[]const u8 = null,

    pub const ParserError = error{
        InvalidValue,
    };

    pub fn init(args: std.process.Args) Parser {
        var iter = args.iterate();
        _ = iter.next(); // skip first argument

        return .{ .argIterator = iter };
    }

    pub fn deinit(self: *Parser) !void {
        self.argIterator.deinit();
    }

    fn next(self: *Parser) ?[]const u8 {
        if (self.peeked) |p| {
            self.peeked = null;
            return p;
        }

        return self.argIterator.next();
    }

    fn peek(self: *Parser) ?[]const u8 {
        if (self.peeked == null) {
            self.peeked = self.argIterator.next();
        }

        return self.peeked;
    }

    pub fn parse(self: *Parser) !?Action {
        while (self.next()) |arg| {
            // NOTE specialcases: help

            if (std.mem.startsWith(u8, arg, "-"))
                continue;

            return std.meta.stringToEnum(Action, arg) orelse error.InvalidAction;
        }

        return null;
    }

    pub fn parseArguments(
        self: *Parser,
        comptime T: type,
        allocator: Allocator,
        cfg: *T,
    ) !void {
        const arena_alloc: Allocator = if (@hasField(T, "_arena")) arena: {
            if (cfg._arena == null) {
                cfg._arena = .init(allocator);
            }

            break :arena cfg._arena.?.allocator();
        };

        while (self.next()) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                return Action.help;
            }

            var key: []const u8 = key: {
                if (std.mem.startsWith(u8, arg, "--")) {
                    break :key arg[2..];
                }

                if (std.mem.startsWith(u8, arg, "-")) {
                    break :key arg[1..];
                }

                continue;
            };

            const value: ?[]const u8 = value: {
                if (std.mem.indexOf(u8, key, "=")) |idx| {
                    defer key = key[0..idx];
                    break :value key[idx + 1 ..];
                }

                break :value if (self.peek()) |nextArg| inner: {
                    if (!std.mem.startsWith(u8, nextArg, "-")) {
                        break :inner self.next();
                    }

                    break :inner null;
                } else null;
            };

            try parseField(T, arena_alloc, cfg, key, value);
        }
    }

    fn parseField(
        comptime T: type,
        allocator: Allocator,
        cfg: *T,
        key: []const u8,
        value: ?[]const u8,
    ) !void {
        const info = @typeInfo(T);

        inline for (info.@"struct".fields) |field| {
            if (field.name[0] != '_' and std.mem.eql(u8, field.name, key)) {
                std.debug.print("Key = {s} >> ", .{key});
                std.debug.print("Value = {?s}\n", .{value});

                const Field = switch (@typeInfo(field.type)) {
                    .optional => |opt| opt.child,
                    else => field.type,
                };

                @field(cfg, field.name) = switch (Field) {
                    bool => try parseBool(value),
                    []const u8 => try parseString(allocator, value),
                    inline u8, u16, u21, u32, u64, usize, i8, i16, i32, i64, isize => |Integer| try parseInt(Integer, value),
                    inline f16, f32, f64, f128, f80 => |Float| try parseFloat(Float, value),
                    else => @compileError("unsupported field type: " ++ @typeName(Field)),
                };
            }
        }
    }

    fn parseString(allocator: Allocator, value: ?[]const u8) ![]const u8 {
        const slice = value orelse return ParserError.InvalidValue;
        const buffer = try allocator.alloc(u8, slice.len);
        @memcpy(buffer, slice);

        return buffer;
    }

    fn parseInt(comptime T: type, value: ?[]const u8) !T {
        return std.fmt.parseInt(T, value orelse return ParserError.InvalidValue, 0) catch return ParserError.InvalidValue;
    }

    fn parseFloat(comptime T: type, value: ?[]const u8) !T {
        return std.fmt.parseFloat(T, value orelse return ParserError.InvalidValue) catch return ParserError.InvalidValue;
    }

    fn parseBool(value: ?[]const u8) !bool {
        const t = &[_][]const u8{ "1", "t", "T", "true" };
        const f = &[_][]const u8{ "0", "f", "F", "false" };
        const v = value orelse return true;

        inline for (t) |str| {
            if (std.mem.eql(u8, v, str)) return true;
        }

        inline for (f) |str| {
            if (std.mem.eql(u8, v, str)) return false;
        }

        return ParserError.InvalidValue;
    }
};
