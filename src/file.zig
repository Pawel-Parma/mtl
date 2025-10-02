const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");
const Node = @import("node.zig");

const File = @This();
allocator: std.mem.Allocator,
path: []const u8,
buffer: []const u8,
tokens: std.ArrayList(Token) = .empty,
position: usize = 0,
line_number: usize = 1,
line_start: usize = 0,
success: bool = true,
ats: std.ArrayList(Node) = .empty,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !File {
    const buffer = try readBuffer(allocator, file_path);
    return .{
        .allocator = allocator,
        .path = file_path,
        .buffer = buffer,
    };
}

pub fn ensureTokensCapacity(self: *File) !void {
    const initialCapacity = @min(512, self.buffer.len / 2);
    try self.tokens.ensureTotalCapacityPrecise(self.allocator, initialCapacity);
}

pub fn printTokens(self: *File) void {
    core.dprint("\nTokens:\n", .{});
    for (self.tokens.items) |token| {
        var string = token.string(self.buffer);
        if (string[0] == '\n') {
            string = "\\n";
        }
        core.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, string });
    }
    core.dprint("\n", .{});
}

pub fn getLine(buffer: []const u8, line_start: usize, start_index: usize, default: usize) []const u8 {
    const line_end = std.mem.indexOfScalarPos(u8, buffer, start_index, '\n') orelse default;
    return buffer[line_start..line_end];
}

fn readBuffer(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);
    return buffer;
}
