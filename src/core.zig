const std = @import("std");
const builtin = @import("builtin");

pub fn panic(code: u8) noreturn {
    std.debug.print("Exiting with code {d}\n", .{code});
    @panic("Exiting");
}

pub fn exit(code: u8) noreturn {
    std.process.exit(code);
}

pub inline fn dprint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}

pub inline fn dprintn(comptime fmt: []const u8) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt ++ "\n", .{});
    }
}

pub inline fn rprint(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

pub inline fn boldStart() void {
    std.debug.print("\x1b[1m", .{});
}

pub inline fn boldEnd() void {
    std.debug.print("\x1b[0m", .{});
}

pub inline fn redStart() void {
    std.debug.print("\x1b[1;31m", .{});
}

pub inline fn redEnd() void {
    std.debug.print("\x1b[0m", .{});
}

pub fn printSourceLine(message: []const u8, file_path: []const u8, line_number: usize, column: usize, line: []const u8) void {
    boldStart();
    rprint("{s}:{d}:{d} ", .{ file_path, line_number, column });
    boldEnd();
    redStart();
    rprint("error: ", .{});
    redEnd();
    rprint("{s}\n", .{message});
    rprint("    {s}\n", .{line});
    var spaces: [256]u8 = undefined;
    const space_count = @min(column, spaces.len);
    @memset(spaces[0..space_count], ' ');
    rprint("    {s}^\n", .{spaces[0..space_count]});
}
