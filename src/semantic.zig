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

pub const Error = error{} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, tokens: []const Token, ast: std.ArrayList(Node)) Semantic {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .tokens = tokens,
        .ast = ast,
        .scopes = .empty,
    };
}

pub fn analyze(self: *Semantic) !void {
    try self.scopes.append(self.allocator, .init(self.allocator));
    // TODO: make global scope lazily analyzed
    for (self.ast.items) |node| {
        try self.semanticPass(node);
    }
}

fn semanticPass(self: *Semantic, node: Node) Error!void {
    switch (node.kind) {
        .Declaration => try self.declarationNode(node),
        .Scope => try self.scopeNode(node),
        else => self.reportError(node, "Unsupported node in semanticPass: {any}", .{node}),
    }
}

fn reportError(self: *Semantic, node: Node, comptime fmt: []const u8, args: anytype) noreturn {
    // TODO: print errors
    const len = self.buffer.len;
    const token = node.token(self.tokens) orelse {
        core.printSourceLine(fmt, args, "mtl/semantic.zig", 0, 0, "EOF", 3);
        core.rprint("Error: ", .{});
        core.rprint(fmt, args);
        core.rprint("\n", .{});
        const n: ?u8 = null;
        const ni = n.? + 1;
        _ = ni;
        core.exit(99);
    };

    const line_info = token.lineInfo(self.buffer);
    const column_number = token.start - line_info.start;
    const line = core.getLine(self.buffer, line_info.start, token.start, len);

    core.printSourceLine(fmt, args, "mtl/semantic.zig", line_info.number, column_number, line, token.len());
    core.rprint("Error: ", .{});
    core.rprint(fmt, args);
    core.rprint("\n", .{});
    core.exit(99);
}

fn scopeOf(self: *Semantic, name: []const u8) ?*std.StringHashMap(Declaration) {
    for (self.scopes.items) |*scope_map| {
        if (scope_map.contains(name)) {
            return scope_map;
        }
    }
    return null;
}

inline fn isInScope(self: *Semantic, name: []const u8) bool {
    return self.scopeOf(name) != null;
}

fn declarationNode(self: *Semantic, node: Node) !void {
    const identifier = node.children[1].token(self.tokens).?;
    const identifier_name = identifier.string(self.buffer);
    if (Declaration.Type.isPrimitive(identifier_name)) {
        self.reportError(node, "Cannot declare variable '{s}', shadows primitive type", .{identifier_name});
    }
    if (self.isInScope(identifier_name)) {
        self.reportError(node, "Shadowing of '{s}' from outer scope is not allowed\n", .{identifier_name});
    }

    const declaration = node.children[0];
    const type_node = node.children[2];
    const expression = node.children[3];
    const expression_type = self.inferType(expression);
    const declared_type: Declaration.Type = if (type_node.token_index) |_| self.resolveType(type_node) else expression_type;

    if (!declared_type.equals(expression_type)) {
        self.reportError(node, "Type mismatch in declaration of '{s}': expected {any}, got {any}\n", .{ identifier_name, declared_type, expression_type });
    }

    var current_scope = &self.scopes.items[self.scopes.items.len - 1];
    const kind: Declaration.Kind = if (declaration.token(self.tokens).?.kind == .Const) .Const else .Var;
    try current_scope.put(identifier_name, .{
        .kind = kind,
        .symbol_type = declared_type,
        .expr = expression,
    });
}

fn scopeNode(self: *Semantic, node: Node) Error!void {
    try self.scopes.append(self.allocator, .init(self.allocator));
    for (node.children) |child| {
        try self.semanticPass(child);
    }
    var last_scope = self.scopes.pop().?;
    last_scope.deinit();
}

fn inferType(self: *Semantic, node: Node) Declaration.Type {
    const name = node.string(self.buffer, self.tokens);
    switch (node.kind) {
        .IntLiteral => return .ComptimeInt,
        .FloatLiteral => return .ComptimeFloat,
        .UnaryMinus => {
            const child_type = self.inferType(node.children[0]);
            if (!child_type.allowsOperation(.UnaryMinus)) {
                self.reportError(node, "Unary minus not allowed on type {any}", .{child_type});
            }
            return child_type;
        },
        .BinaryPlus, .BinaryMinus, .BinaryStar, .BinarySlash => {
            const left_type = self.inferType(node.children[0]);
            const right_type = self.inferType(node.children[1]);
            if (left_type.equals(right_type)) {
                if (!left_type.allowsOperation(node.kind)) {
                    self.reportError(node, "Operation {any} not allowed on type {any}", .{ node.kind, left_type });
                }
                if (!right_type.allowsOperation(node.kind)) {
                    self.reportError(node, "Operation {any} not allowed on type {any}", .{ node.kind, right_type });
                }
                return left_type;
            }
            self.reportError(node, "Type mismatch in binary operator: expected {any}, got {any}", .{ left_type, right_type });
        },
        .Identifier => {
            if (Declaration.Type.isPrimitive(name)) {
                return .Type;
            }
            if (self.scopeOf(name)) |scope| {
                return scope.get(name).?.symbol_type;
            }
            self.reportError(node, "Undefined identifier '{s}'", .{name});
        },
        .Expression => {
            const first_expr_type = self.inferType(node.children[0]);
            for (node.children) |expr| {
                const expr_type = self.inferType(expr);
                if (!first_expr_type.equals(expr_type)) {
                    self.reportError(node, "Type mismatch in expression: expected {any}, got {any}", .{ first_expr_type, expr_type });
                }
            }
            return first_expr_type;
        },
        else => self.reportError(node, "Unsupported node kind for inferType: {any}", .{node}),
    }
}

fn resolveType(self: *Semantic, type_node: Node) Declaration.Type {
    const type_name = type_node.string(self.buffer, self.tokens);
    if (Declaration.Type.lookup(type_name)) |t| {
        return t;
    } else {
        if (self.scopeOf(type_name)) |scope_map| {
            const declaration = scope_map.get(type_name).?;
            const declaration_name = declaration.expr.?.string(self.buffer, self.tokens);
            if (Declaration.Type.lookup(declaration_name)) |t| {
                return t;
            } else if (self.scopeOf(declaration_name)) |scope| {
                const inner_declaration = scope.get(declaration_name).?;
                const inner_declaration_name = inner_declaration.expr.?.string(self.buffer, self.tokens);
                if (Declaration.Type.lookup(inner_declaration_name)) |t| {
                    return t;
                }
                self.reportError(type_node, "Type alias '{s}' does not refer to a primitive type\n", .{inner_declaration_name});
            } else {
                self.reportError(type_node, "Type alias '{s}' does not refer to a primitive type\n", .{type_name});
            }
        } else {
            self.reportError(type_node, "Unknown type '{s}'\n", .{type_name});
        }
    }
}
