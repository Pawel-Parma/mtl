const std = @import("std");

const Printer = @import("printer.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");

// TODO: refactior entire file
const File = @This();
allocator: std.mem.Allocator,
printer: Printer,
path: []const u8,
buffer: []const u8,
tokens: std.ArrayList(Token) = .empty,
position: u32 = 0,
current: u32 = 0,
line_number: u32 = 1,
line_start: u32 = 0,
success: bool = true,
ast: std.ArrayList(Node) = .empty,
scopes: std.ArrayList(std.StringHashMap(Declaration)),

pub fn init(allocator: std.mem.Allocator, printer: Printer, file_path: []const u8) !File {
    const buffer = try readBuffer(allocator, file_path);
    return .{
        .allocator = allocator,
        .printer = printer,
        .path = file_path,
        .buffer = buffer,
        .scopes = .empty,
    };
}

pub fn ensureTokensCapacity(self: *File) !void {
    const initialCapacity = @min(512, self.buffer.len / 2);
    try self.tokens.ensureTotalCapacityPrecise(self.allocator, initialCapacity);
}
pub fn ensureAstCapacity(self: *File) !void {
    const initialCapacity = @min(512, self.tokens.items.len / 2);
    try self.ast.ensureTotalCapacity(self.allocator, initialCapacity);
}

pub fn printTokens(self: *File) void {
    self.printer.dprint("\nTokens {d}:\n", .{self.tokens.items.len});
    for (self.tokens.items, 0..) |token, i| {
        switch (token.kind) {
            .Newline, .Comment, .EscapeSequence => continue,
            else => {},
        }
        const string = token.string(self.buffer);
        self.printer.dprint("{d}: ", .{i});
        self.printer.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, string });
    }
    self.printer.dprint("\nTokens End\n", .{});
    self.printer.flush();
}

pub fn printAst(self: *File) void {
    self.printer.dprint("AST:\n", .{});
    for (self.ast.items) |node| {
        self.printNode(node, 0);
    }
    self.printer.dprint("\n", .{});
    self.printer.flush();
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

    var i: u32 = 0;
    while (i < node.children) : (i += 1) {
        self.printNode(child, depth + 1); // TODO:
    }

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
