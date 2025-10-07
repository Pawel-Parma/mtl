const std = @import("std");

const Printer = @import("printer.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");

// TODO:
const File = @This();
allocator: std.mem.Allocator,
printer: Printer,
path: []const u8,
buffer: []const u8,
tokens: std.ArrayList(Token) = .empty,
position: usize = 0,
line_number: usize = 1,
line_start: usize = 0,
success: bool = true,
ast: std.ArrayList(Node) = .empty,

pub fn init(allocator: std.mem.Allocator, printer: Printer, file_path: []const u8) !File {
    const buffer = try readBuffer(allocator, file_path);
    return .{
        .allocator = allocator,
        .printer = printer,
        .path = file_path,
        .buffer = buffer,
    };
}

pub fn ensureTokensCapacity(self: *File) !void {
    const initialCapacity = @min(512, self.buffer.len / 2);
    try self.tokens.ensureTotalCapacityPrecise(self.allocator, initialCapacity);
}

pub fn printTokens(self: *File) void {
    self.printer.dprint("\nTokens:\n", .{});
    for (self.tokens.items) |token| {
        var string = token.string(self.buffer);
        if (string[0] == '\n') {
            string = "\\n";
        }
        self.printer.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, string });
    }
    self.printer.dprint("\n", .{});
}

pub fn printAst(self: *File) void {
    self.printer.dprint("AST:\n", .{});
    for (self.ast.items) |node| {
        self.printNode(node, 0);
    }
    self.printer.dprint("\n", .{});
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

pub fn printNode(self: *File, node: Node, depth: usize) void {
    for (0..depth) |_| {
        self.printer.dprint("  ", .{});
    }
    self.printer.dprint("{any} (token_index={any})", .{ node.kind, node.token_index });
    if (node.token(self.tokens.items)) |t| {
        self.printer.dprint(" (token.kind={any}) (token.string=\"{s}\")", .{ t.kind, t.string(self.buffer) });
    }
    self.printer.dprint("\n", .{});

    for (node.children) |child| {
        self.printNode(child, depth + 1);
    }
}

pub fn lineInfo(self: *File, token: Token) struct {
    number: usize,
    start: usize,
} {
    var line_number: usize = 1;
    var line_start: usize = 0;
    for (self.buffer[0..token.start], 0..) |c, i| {
        if (c == '\n') {
            line_number += 1;
            line_start = i + 1;
        }
    }
    return .{ .number = line_number, .start = line_start };
}
