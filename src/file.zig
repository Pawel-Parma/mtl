const std = @import("std");

const Printer = @import("printer.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");

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
    self.printer.dprint("Tokens {d}:\n", .{self.tokens.items.len});
    for (self.tokens.items, 0..) |token, i| {
        switch (token.kind) {
            .Newline, .Comment, .EscapeSequence => continue,
            else => {},
        }
        const string = token.string(self);
        self.printer.dprint("{d}: ", .{i});
        self.printer.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, string });
    }
    self.printer.dprint("Tokens End\n\n", .{});
    self.printer.flush();
}

pub fn printAst(self: *File) void {
    self.printer.dprint("AST {d}:\n", .{self.ast.items.len});
    var depth_time: std.ArrayList(u32) = .empty;
    for (self.ast.items) |node| {
        for (0..depth_time.items.len) |_| {
            self.printer.dprint("  ", .{});
        }

        self.printer.dprint("{any} (children={d}) (token_index={any})", .{ node.kind, node.children, node.token_index });
        if (node.token(self)) |t| {
            self.printer.dprint(" (token.kind={any}) (token.string=\"{s}\")", .{ t.kind, t.string(self) });
        }
        self.printer.dprint("\n", .{});

        if (depth_time.items.len > 0) {
            depth_time.items[depth_time.items.len - 1] -= 1;
        }
        if (node.children > 0) {
            depth_time.append(self.allocator, node.children) catch @panic("could not print OOM");
        }
        while (depth_time.items.len > 0 and depth_time.getLast() == 0) {
            _ = depth_time.pop();
        }
    }
    self.printer.dprint("AST End\n\n", .{});
    self.printer.flush();
}

pub fn printScopes(self: *File) void {
    self.printer.dprint("Scopes:\n", .{});

    self.printer.dprint(" Scope {s} Global:\n", .{self.path});
    self.printScope(self.global_scope);
    for (self.all_scopes.items, 0..) |scope, i| {
        self.printer.dprint(" Scope {d}:\n", .{i});
        self.printScope(scope);
    }
    self.printer.dprint("Scopes End\n\n", .{});
    self.printer.flush();
}

fn printScope(self: *File, scope: *std.StringHashMap(Declaration)) void {
    var max_kind_len: usize = 0;
    var max_name_len: usize = 0;
    var max_smbl_len: usize = 0;
    var it = scope.iterator();
    while (it.next()) |entry| {
        const decl = entry.value_ptr.*;
        const name = entry.key_ptr.*;

        const kind_str = std.fmt.allocPrint(self.allocator, "{any}", .{decl.kind}) catch @panic("OOM");
        const smbl_str = std.fmt.allocPrint(self.allocator, "{any}", .{decl.symbol_type}) catch @panic("OOM");
        if (kind_str.len > max_kind_len) max_kind_len = kind_str.len;
        if (name.len > max_name_len) max_name_len = name.len;
        if (smbl_str.len > max_smbl_len) max_smbl_len = smbl_str.len;
    }

    var scope_it = scope.iterator();
    while (scope_it.next()) |entry| {
        const name = entry.key_ptr.*;
        const decl = entry.value_ptr.*;

        const kind_str = std.fmt.allocPrint(self.allocator, "{any}", .{decl.kind}) catch @panic("OOM");
        self.printer.dprint("  {s}", .{kind_str});
        for (0..(max_kind_len - kind_str.len)) |_| self.printer.dprint(" ", .{});
        self.printer.dprint(" | ", .{});

        self.printer.dprint("{s}", .{name});
        for (0..(max_name_len - name.len)) |_| self.printer.dprint(" ", .{});
        self.printer.dprint(" | ", .{});

        const smbl_str = std.fmt.allocPrint(self.allocator, "{any}", .{decl.symbol_type}) catch @panic("OOM");
        self.printer.dprint(" {s} ", .{smbl_str});
        for (0..(max_smbl_len - smbl_str.len)) |_| self.printer.dprint(" ", .{});
        self.printer.dprint(" | ", .{});

        if (decl.node_index) |idx| {
            self.printer.dprint(" {any}", .{self.ast.items[idx]});
        }
        self.printer.dprint("\n", .{});
    }
}
