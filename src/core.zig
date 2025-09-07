const std = @import("std");
const builtin = @import("builtin");

pub fn panic(code: u8) noreturn {
    std.debug.print("Exiting with code {d}\n", .{code});
    @panic("Exiting");
}

pub const Code = enum(u8) {
    OutOfMemory = 50,
};

pub fn exitCode(reason: []const u8, code: Code) noreturn {
    rprint("{s}: {any}\n", .{ reason, code });
    exit(@intFromEnum(code));
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
    boldEnd();
    redStart();
    rprint("error: ", .{});
    redEnd();
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

pub fn readFileToBuffer(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);
    return buffer;
}

pub fn getLine(buffer: []const u8, line_start: usize, start_index: usize, default: usize) []const u8 {
    const line_end = std.mem.indexOfScalarPos(u8, buffer, start_index, '\n') orelse default;
    return buffer[line_start..line_end];
}