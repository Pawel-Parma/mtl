const std = @import("std");
const core = @import("core.zig");
const primitive = @import("primitive.zig");

const Token = @import("token.zig");
const Node = @import("node.zig");

const Semantic = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
tokens: []const Token,
ast: std.ArrayList(Node),
scopes: std.ArrayList(std.StringHashMap(Declaration)),
// TODO: refactor

pub const Declaration = struct {
    kind: Kind,
    symbol_type: primitive.Type,
    expr: ?Node,

    pub const Kind = enum {
        Var,
        Const,
    };
};

pub const Error = error{
    TypeMismatch,
    UndefinedIdentifier,
    OutOfMemory,
};

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, tokens: []const Token, ast: std.ArrayList(Node)) Semantic {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .tokens = tokens,
        .ast = ast,
        .scopes = .empty,
    };
}

pub fn deinit(self: *Semantic) void {
    self.scopes.deinit(self.allocator);
}

pub fn analyze(self: *Semantic) !void {
    try self.scopes.append(self.allocator, std.StringHashMap(Declaration).init(self.allocator));
    // TODO: make global scope lazly analized
    for (self.ast.items) |node| {
        try self.semanticPass(node, 0);
    }
    return;
}

fn semanticPass(self: *Semantic, node: Node, depth: usize) Error!void {
    switch (node.kind) {
        .VarDeclaration, .ConstDeclaration => try self.declaration(node, depth),
        .Scope => try self.scope(node, depth),
        else => self.unsupportedNode(node),
    }
}

fn isInScope(self: *Semantic, name: []const u8) ?*std.StringHashMap(Declaration) {
    for (self.scopes.items) |*scope_map| {
        if (scope_map.contains(name)) {
            return scope_map;
        }
    }
    return null;
}

inline fn declaration(self: *Semantic, node: Node, depth: usize) !void {
    _ = depth;
    const declaration_kind: Token.Kind = switch (node.kind) {
        .VarDeclaration => .Var,
        .ConstDeclaration => .Const,
        else => unreachable,
    };
    const name_identifier_node = node.children[0];
    const type_identifier_node = node.children[1];
    const expr_node = node.children[2];

    const name = name_identifier_node.token(self.tokens).?.string(self.buffer);
    if (primitive.isPrimitiveType(name)) {
        core.rprint("Error: Cannot declare variable '{s}', shadows primitive type \n", .{name});
        core.exit(12);
    }

    var current_scope = &self.scopes.items[self.scopes.items.len - 1];
    var i = self.scopes.items.len;
    while (i > 1) : (i -= 1) {
        if (self.scopes.items[i - 2].contains(name)) {
            core.rprint("Error: Shadowing of '{s}' from outer scope is not allowed\n", .{name});
            core.exit(11);
        }
    }

    const kind: Declaration.Kind = switch (declaration_kind) {
        .Var => .Var,
        .Const => .Const,
        else => unreachable,
    };

    const expr_type = try self.inferType(expr_node);
    var symbol_type: ?primitive.Type = null;
    const type_identifier_token = type_identifier_node.token(self.tokens);
    if (type_identifier_token) |token| {
        const type_name = token.string(self.buffer);
        if (!primitive.isPrimitiveType(type_name)) {
            if (self.isInScope(type_name)) |scope_map| {
                const decl = scope_map.get(type_name).?;
                symbol_type = decl.symbol_type;
            } else {
                core.rprint("Error: Unknown type '{s}'\n", .{type_name});
                core.exit(12);
            }
        } else {
            symbol_type = primitive.lookup(type_name).?;
        }
    } else {
        symbol_type = expr_type;
    }

    if (!symbol_type.?.equals(expr_type)) {
        core.rprint("Error: Type mismatch in declaration of '{s}': expected {any}, got {any}\n", .{ name, symbol_type, expr_type });
        core.exit(12);
    }

    try current_scope.put(name, .{
        .kind = kind,
        .symbol_type = symbol_type.?,
        .expr = expr_node,
    });
}

inline fn scope(self: *Semantic, node: Node, depth: usize) Error!void {
    try self.scopes.append(self.allocator, .init(self.allocator));
    for (node.children) |child| {
        try self.semanticPass(child, depth + 1);
    }
    var last_scope = self.scopes.pop().?;
    last_scope.deinit();
}

inline fn unsupportedNode(self: *Semantic, node: Node) noreturn {
    _ = self;
    core.rprint("Unhandled node kind {any}\n", .{node.kind});
    core.exit(99);
}

fn inferType(self: *Semantic, node: Node) !primitive.Type {
    const token = node.token(self.tokens).?;
    const name = token.string(self.buffer);

    switch (node.kind) {
        .NumberLiteral => {
            const dot_pos = std.mem.indexOf(u8, name, ".") orelse return .ComptimeInt;
            for (name[dot_pos + 1 ..]) |c| {
                if (c != '0') {
                    return .ComptimeFloat;
                }
            }
            return .ComptimeInt;
        },
        .Identifier => {
            if (self.isInScope(name)) |scope_map| {
                const decl = scope_map.get(name).?;
                return decl.symbol_type;
            }
            if (primitive.isPrimitiveType(name)) {
                return primitive.lookup(name).?;
            }
            core.rprint("Error: Undefined identifier '{s}'\n", .{name});
            return error.UndefinedIdentifier;
        },
        .UnaryOperator => {
            return try self.inferType(node.children[0]);
        },
        .BinaryOperator => {
            const left_type = try self.inferType(node.children[0]);
            const right_type = try self.inferType(node.children[1]);
            if (!left_type.equals(right_type)) {
                core.rprint("Error: Type mismatch in binary operator: expected {any}, got {any}\n", .{ left_type, right_type });
                return error.TypeMismatch;
            }
            return left_type;
        },
        .Expression => {
            var exprs: [64]primitive.Type = undefined;
            for (node.children, 0..) |child, i| {
                exprs[i] = try self.inferType(child);
            }
            for (exprs) |expr| {
                if (!expr.equals(exprs[0])) {
                    core.rprint("Error: Type mismatch in binary operator: expected {any}, got {any}\n", .{ exprs[0], expr });
                    return error.TypeMismatch;
                }
            }
            return exprs[0];
        },
        else => {
            core.dprintn("TODO");
            core.dprint(" (in inferType for node kind {any})\n", .{node.kind});
            return .DebugVal;
        },
    }
}
