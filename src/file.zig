const std = @import("std");

const Printer = @import("printer.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");
const options = @import("options.zig");

const File = @This();
allocator: std.mem.Allocator,
printer: Printer,
path: []const u8,
buffer: []const u8,
tokens: std.ArrayList(Token) = .empty,
position: u32 = 0,
current: u32 = 0,
selected: u32 = 0,
line_number: u32 = 1,
line_start: u32 = 0,
success: bool = true,
ast: std.ArrayList(Node) = .empty,
global_scope: *std.StringHashMap(Declaration),
all_scopes: std.ArrayList(*std.StringHashMap(Declaration)),
scopes: std.ArrayList(*std.StringHashMap(Declaration)),

pub fn init(allocator: std.mem.Allocator, printer: Printer, file_path: []const u8) !File {
    return .{
        .allocator = allocator,
        .printer = printer,
        .path = file_path,
        .buffer = try readBuffer(allocator, file_path),
        .global_scope = try makeScope(allocator),
        .all_scopes = .empty,
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

pub fn makeScope(allocator: std.mem.Allocator) !*std.StringHashMap(Declaration) {
    const scope = try allocator.create(std.StringHashMap(Declaration));
    scope.* = .init(allocator);
    return scope;
}

pub fn appendScope(self: *File, scope: *std.StringHashMap(Declaration)) !void {
    try self.scopes.append(self.allocator, scope);
    try self.all_scopes.append(self.allocator, scope);
}

pub fn popScope(self: *File) void {
    _ = self.scopes.pop().?;
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

pub fn printTokens(self: *File) void {
    if (!options.debug) {
        return;
    }
    self.printer.printColor("\n=== TOKENS (<Yellow:{d}>) ===\n", .{self.tokens.items.len});
    const max_len = std.fmt.count("{d}", .{self.tokens.items.len});
    for (self.tokens.items, 0..) |token, i| {
        self.printer.printColor("<Magenta:{d}>: ", .{i});
        const current_len = std.fmt.count("{d}", .{i});
        self.printer.pad(max_len - current_len);
        self.printer.printColor("<Blue:{any}> (start=<Yellow:{d}>) (end=<Yellow:{d}>) (token.string=<Green:\"{s}\">)\n", .{
            token.kind,
            token.start,
            token.end,
            token.string(self),
        });
    }
    self.printer.printString("=== TOKENS END ===\n");
    self.printer.flush();
}

pub fn printAst(self: *File) void {
    if (!options.debug) {
        return;
    }
    self.printer.printColor("\n=== AST (<Yellow:{d}>) ===\n", .{self.ast.items.len});
    var depth_time: std.ArrayList(u32) = .empty;
    for (self.ast.items) |node| {
        for (depth_time.items, 0..) |remaining, i| {
            if (depth_time.items.len - 1 == i) {
                self.printer.printString(if (remaining > 1) "├─" else "└─");
            } else {
                self.printer.printString(if (remaining > 0) "│  " else "   ");
            }
        }
        const kind_color_code: Printer.Ansi.Code = if (depth_time.items.len % 2 == 1) .Blue else .Magenta;
        self.printer.printCode(kind_color_code, "{any}", .{node.kind});
        self.printer.printColor(" (children=<Yellow:{d}>) (token_index=", .{node.children});
        const token_index_color_code: Printer.Ansi.Code = if (node.token_index) |_| .Yellow else .Red;
        self.printer.printCode(token_index_color_code, "{?d}", .{node.token_index});
        if (node.token(self)) |token| {
            self.printer.printColor(") (token.kind=<Cyan:{any}>) (token_string=<Green:\"{s}\">", .{
                token.kind,
                token.string(self),
            });
        }
        self.printer.printString(")\n");

        if (depth_time.items.len > 0) {
            depth_time.items[depth_time.items.len - 1] -= 1;
        }
        if (node.children > 0) {
            depth_time.append(self.allocator, node.children) catch @panic("Could not append OutOfMemory");
        }
        while (depth_time.items.len > 0 and depth_time.getLast() == 0) {
            _ = depth_time.pop().?;
        }
    }
    self.printer.printString("=== AST END ===\n");
    self.printer.flush();
}

pub fn printScopes(self: *File) void {
    if (!options.debug) {
        return;
    }
    self.printer.printColor("\n=== SCOPES (<Yellow:{d}>) ===\n", .{self.all_scopes.items.len + 1});
    self.printer.printColor(" Scope <Yellow:global> {s}:\n", .{self.path});
    self.printScope(self.global_scope);
    for (self.all_scopes.items, 0..) |scope, i| {
        self.printer.printColor(" Scope <Yellow:{d}>:\n", .{i});
        self.printScope(scope);
    }
    self.printer.printString("=== SCOPES END ===\n\n");
    self.printer.flush();
}

fn printScope(self: *File, scope: *std.StringHashMap(Declaration)) void {
    var max_kind_len: usize = 0;
    var max_name_len: usize = 0;
    var max_symbol_len: usize = 0;
    var it = scope.iterator();
    while (it.next()) |entry| {
        const decl = entry.value_ptr.*;
        const name = entry.key_ptr.*;

        const kind_len = std.fmt.count("{any}", .{decl.kind});
        const smbl_len = std.fmt.count("{any}", .{decl.symbol_type});
        if (kind_len > max_kind_len) max_kind_len = kind_len;
        if (name.len > max_name_len) max_name_len = name.len;
        if (smbl_len > max_symbol_len) max_symbol_len = smbl_len;
    }

    var scope_it = scope.iterator();
    while (scope_it.next()) |entry| {
        const name = entry.key_ptr.*;
        const declaration = entry.value_ptr.*;

        self.printer.printColor("  <Blue:{any}>", .{declaration.kind});
        const kind_len = std.fmt.count("{any}", .{declaration.kind});
        self.printer.pad(max_kind_len - kind_len);

        self.printer.printColor(" | <Green:{s}>", .{name});
        self.printer.pad(max_name_len - name.len);

        self.printer.printColor(" | <Cyan:{any}>", .{declaration.symbol_type});
        const symbol_len = std.fmt.count("{any}", .{declaration.symbol_type});
        self.printer.pad(max_symbol_len - symbol_len);
        self.printer.printString(" |\n");
    }
}
