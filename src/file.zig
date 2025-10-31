const std = @import("std");

const Printer = @import("printer.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");
const options = @import("options.zig");

// TODO: refactor entire file
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
    self.printer.printString("\n=== TOKENS (");
    self.printer.printColor(.Yellow, "{d}", .{self.tokens.items.len});
    self.printer.printString(") ===\n");
    const max_len = std.fmt.count("{d}", .{self.tokens.items.len});
    for (self.tokens.items, 0..) |token, i| {
        switch (token.kind) {
            .Newline, .Comment, .EscapeSequence => continue,
            else => {},
        }
        self.printer.printColor(.Magenta, "{d}", .{i});
        self.printer.printString(":");
        const current_len = std.fmt.count("{d}", .{i});
        self.printer.pad(max_len - current_len);
        self.printer.printString("  ");
        self.printer.printColor(.Blue, "{any}", .{token.kind});
        // self.printer.print(" (start={any}, end={any}) ", .{ token.start, token.end });
        self.printer.printString(" (start=");
        self.printer.printColor(.Yellow, "{any}", .{token.start});
        self.printer.printString(") (end=");
        self.printer.printColor(.Yellow, "{any}", .{token.end});
        self.printer.printString(") (token.string=");
        self.printer.printColor(.Green, "\"{s}\"", .{token.string(self)});
        self.printer.printString(")\n");
    }
    self.printer.printString("=== TOKENS END ===\n");
    self.printer.flush();
}

pub fn printAst(self: *File) void {
    if (!options.debug) {
        return;
    }
    self.printer.printString("\n=== AST (");
    self.printer.printColor(.Yellow, "{d}", .{self.ast.items.len});
    self.printer.printString(") ===\n");
    var depth_time: std.ArrayList(u32) = .empty;
    for (self.ast.items) |node| {
        for (0..depth_time.items.len) |i| {
            const remaining = depth_time.items[i];
            if (i == depth_time.items.len - 1) {
                if (remaining > 1) {
                    self.printer.printString("├─");
                } else {
                    self.printer.printString("└─");
                }
            } else {
                if (remaining > 0)
                    self.printer.printString("│  ")
                else
                    self.printer.printString("   ");
            }
        }
        if (depth_time.items.len % 2 == 1) {
            self.printer.printColor(.Blue, "{any}", .{node.kind});
        } else {
            self.printer.printColor(.Magenta, "{any}", .{node.kind});
        }
        self.printer.printString(" (children=");
        self.printer.printColor(.Yellow, "{d}", .{node.children});
        self.printer.printString(") (token_index=");
        const token_index_color_code: Printer.Ansi.Code = if (node.token_index) |_| .Yellow else .Red;
        self.printer.printColor(token_index_color_code, "{?d}", .{node.token_index});
        self.printer.printString(")");
        if (node.token(self)) |t| {
            self.printer.printString(" (token.kind=");
            self.printer.printColor(.Cyan, "{any}", .{t.kind});
            self.printer.printString(") (token.string=");
            self.printer.printColor(.Green, "\"{s}\"", .{t.string(self)});
            self.printer.printString(")");
        }
        self.printer.printString("\n");

        if (depth_time.items.len > 0) {
            depth_time.items[depth_time.items.len - 1] -= 1;
        }
        if (node.children > 0) {
            depth_time.append(self.allocator, node.children) catch @panic("could not append OOM");
        }
        while (depth_time.items.len > 0 and depth_time.getLast() == 0) {
            _ = depth_time.pop();
        }
    }
    self.printer.printString("=== AST END ===\n");
    self.printer.flush();
}

pub fn printScopes(self: *File) void {
    if (!options.debug) {
        return;
    }
    self.printer.printString("\n=== SCOPES (");
    self.printer.printColor(.Yellow, "{d}", .{self.all_scopes.items.len});
    self.printer.printString(") ===\n");

    self.printer.printString(" Scope ");
    self.printer.printColor(.Yellow, "global", .{});
    self.printer.print(" {s}:\n", .{self.path});
    self.printScope(self.global_scope);
    for (self.all_scopes.items, 0..) |scope, i| {
        self.printer.printString(" Scope ");
        self.printer.printColor(.Yellow, "{d}", .{i});
        self.printer.printString(":\n");
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
        const decl = entry.value_ptr.*;

        self.printer.printString("  ");
        self.printer.printColor(.Blue, "{any}", .{decl.kind});
        const kind_len = std.fmt.count("{any}", .{decl.kind});
        self.printer.pad(max_kind_len - kind_len);
        self.printer.printString(" | ");

        self.printer.printColor(.Green, "{s}", .{name});
        self.printer.pad(max_name_len - name.len);
        self.printer.printString(" | ");

        self.printer.printColor(.Cyan, "{any}", .{decl.symbol_type});
        const symbol_len = std.fmt.count("{any}", .{decl.symbol_type});
        self.printer.pad(max_symbol_len - symbol_len);
        self.printer.printString(" |\n");
    }
}
