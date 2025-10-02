const std = @import("std");
const builtin = @import("builtin");

pub fn exit(code: u8) noreturn {
    std.process.exit(code);
}

pub fn dprint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}

pub fn rprint(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

pub fn boldStart() void {
    rprint("\x1b[1m", .{});
}

pub fn redStart() void {
    rprint("\x1b[1;31m", .{});
}

pub fn ansiiReset() void {
    rprint("\x1b[0m", .{});
}

pub fn printSourceLine(
    comptime message: []const u8,
    args: anytype,
    file_path: []const u8,
    line_number: usize,
    column: usize,
    line: []const u8,
    token_length: usize,
) void {
    boldStart();
    rprint("{s}:{d}:{d} ", .{ file_path, line_number, column });
    ansiiReset();
    redStart();
    rprint("error: ", .{});
    ansiiReset();
    rprint(message, args);
    rprint("    {s}\n", .{line});
    var spaces: [256]u8 = undefined;
    const space_count = @min(column, spaces.len);
    @memset(spaces[0..space_count], ' ');
    rprint("    {s}^", .{spaces[0..space_count]});
    var t: usize = 1;
    while (t < token_length and column + t < line.len and line[column + t] != '\n') : (t += 1) {
        rprint("~", .{});
    }
    rprint("\n", .{});
}
