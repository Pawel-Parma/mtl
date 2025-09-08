const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");

const Semantic = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
tokens: []const Token,
ast: std.ArrayList(Node),
scopes: std.ArrayList(std.StringHashMap(Declaration)),
depth: usize,
// TODO: refactor

pub const Error = error{
    
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, tokens: []const Token, ast: std.ArrayList(Node)) Semantic {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .tokens = tokens,
        .ast = ast,
        .scopes = .empty,
        .depth = 0,
    };
}

pub fn analyze(self: *Semantic) !void {
    try self.scopes.append(self.allocator, std.StringHashMap(Declaration).init(self.allocator));
    // TODO: make global scope lazly analized
    for (self.ast.items) |node| {
        try self.semanticPass(node);
    }
    return;
}

fn semanticPass(self: *Semantic, node: Node) Error!void {
    switch (node.kind) {
        .VarDeclaration, .ConstDeclaration => try self.declarationNode(node),
        .Scope => try self.scopeNode(node),
        else => self.reportError("Unsupported node in semanticPass: {any}", .{node}),
    }
}

fn reportError(self: *Semantic, comptime fmt: []const u8, args: anytype) noreturn {
    _ = self;
    core.rprint("Error: ", .{});
    core.rprint(fmt, args);
    core.rprint("\n", .{});
    core.exit(99);
}

fn isInScope(self: *Semantic, name: []const u8) ?*std.StringHashMap(Declaration) {
    for (self.scopes.items) |*scope_map| {
        if (scope_map.contains(name)) {
            return scope_map;
        }
    }
    return null;
}

fn declarationNode(self: *Semantic, node: Node) !void {
    const name = node.children[0].token(self.tokens).?.string(self.buffer);
    if (Declaration.Type.isPrimitiveType(name)) {
        self.reportError("Cannot declare variable '{s}', shadows primitive type", .{name});
    }
    var i = self.scopes.items.len;
    while (i > 1) : (i -= 1) {
        if (self.scopes.items[i - 2].contains(name)) {
            self.reportError("Shadowing of '{s}' from outer scope is not allowed\n", .{name});
        }
    }

    const expr_node = node.children[2];
    const expr_type = self.inferType(expr_node);
    var symbol_type: ?Declaration.Type = null;
    const type_identifier_node = node.children[1];
    if (type_identifier_node.token_index) |_| {
        const token = type_identifier_node.token(self.tokens).?;
        const type_name = token.string(self.buffer);
        if (!Declaration.Type.isPrimitiveType(type_name)) {
            if (self.isInScope(type_name)) |scope_map| {
                const decl = scope_map.get(type_name).?;
                symbol_type = decl.symbol_type;
            } else {
                self.reportError("Unknown type '{s}'\n", .{type_name});
            }
        } else {
            symbol_type = Declaration.Type.lookup(type_name).?;
        }
    } else {
        symbol_type = expr_type;
    }

    if (!symbol_type.?.equals(expr_type)) {
        self.reportError("Type mismatch in declaration of '{s}': expected {any}, got {any}\n", .{ name, symbol_type, expr_type });
    }

    var current_scope = &self.scopes.items[self.scopes.items.len - 1];
    try current_scope.put(name, .{
        .kind = switch (node.kind) {
            .VarDeclaration => .Var,
            .ConstDeclaration => .Const,
            else => unreachable,
        },
        .symbol_type = symbol_type.?,
        .expr = expr_node,
    });
}

fn scopeNode(self: *Semantic, node: Node) Error!void {
    try self.scopes.append(self.allocator, .init(self.allocator));
    for (node.children) |child| {
        self.depth += 1;
        try self.semanticPass(child);
    }
    var last_scope = self.scopes.pop().?;
    last_scope.deinit();
    self.depth -= 1;
}

fn inferType(self: *Semantic, node: Node) Declaration.Type {
    const token = node.token(self.tokens).?;
    const name = token.string(self.buffer);
    switch (node.kind) {
        .IntLiteral, .FloatLiteral => |literal| return switch (literal) {
            .IntLiteral => .ComptimeInt,
            .FloatLiteral => .ComptimeFloat,
            else => unreachable,
        },
        .UnaryOperator => return self.inferType(node.children[0]), // TODO: add operator validation
        .BinaryOperator => {
            const left_type = self.inferType(node.children[0]);
            const right_type = self.inferType(node.children[1]);
            if (left_type.equals(right_type)) {
                // TODO: add operator validation
                return left_type;
            }
            self.reportError("Type mismatch in binary operator: expected {any}, got {any}", .{ left_type, right_type });
        },
        .Identifier => {
            if (Declaration.Type.lookup(name)) |t| {
                return t;
            }
            if (self.isInScope(name)) |scope| {
                return scope.get(name).?.symbol_type;
            }
            self.reportError("Undefined identifier '{s}'", .{name});
        },
        .Expression => {
            const first_expr_type = self.inferType(node.children[0]);
            for (node.children) |expr| {
                const expr_type = self.inferType(expr);
                if (!first_expr_type.equals(expr_type)) {
                    self.reportError("Type mismatch in binary operator: expected {any}, got {any}", .{ first_expr_type, expr_type });
                }
            }
            return first_expr_type;
        },
        else => self.reportError("Unsupported node kind for inferType: {any}", .{node}),
    }
}
