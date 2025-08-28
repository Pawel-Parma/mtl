const std = @import("std");
const core = @import("core.zig");
const primitive = @import("primitive.zig");

const Token = @import("tokenizer.zig").Token;
const Node = @import("parser.zig").Node;

const DeclarationMap = std.StringHashMap(Declaration);
const Scopes = std.ArrayList(DeclarationMap);

const Semantic = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
tokens: []const Token,
ast: Node.List,
scopes: Scopes,

pub const Declaration = struct {
    kind: Kind,
    symbol_type: primitive.Type,
    expr: ?Node,

    pub const Kind = enum {
        Var,
        Const,
    };
};

pub const Error = std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, tokens: []const Token, ast: Node.List) Semantic {
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
    core.dprint("\nAST:\n", .{});
    self.printAst();
    core.dprint("\n\n", .{});

    try self.scopes.append(self.allocator, std.StringHashMap(Declaration).init(self.allocator));
    // TODO: make global scope lazly analized
    for (self.ast.items) |node| {
        try self.semanticPass(node, 0);
    }
    return;
}

fn semanticPass(self: *Semantic, node: Node, depth: usize) Error!void {
    var indent_buf: [32]u8 = undefined;
    const indent = indent_buf[0..@min(depth * 2, indent_buf.len)];
    for (indent) |*c| c.* = ' ';

    if (node.token_index) |token_index| {
        const token = node.getToken(self.tokens).?;
        const token_text = token.getName(self.buffer);
        core.dprint("{s}{any} (token_index={any}) (token_kind={any}) (token_text=\"{s}\")\n", .{ indent, node.kind, token_index, token.kind, token_text });
    } else {
        core.dprint("{s}{any} (token_index=null)\n", .{ indent, node.kind });
    }
    switch (node.kind) {
        .Declaration => try self.declaration(node, depth),
        .Scope => try self.scope(node, depth),
        else => self.unsupportedNode(node),
    }
}

fn isInScope(self: *Semantic, name: []const u8) ?*DeclarationMap {
    for (self.scopes.items) |*scope_map| {
        if (scope_map.contains(name)) {
            return scope_map;
        }
    }
    return null;
}

inline fn declaration(self: *Semantic, node: Node, depth: usize) !void {
    _ = depth;
    const declaration_node = node.children.items[0];
    const name_identifier_node = node.children.items[1];
    const type_identifier_node = node.children.items[2];
    const expr_node = node.children.items[3];

    const name = name_identifier_node.getToken(self.tokens).?.getName(self.buffer);
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

    const kind: Declaration.Kind = switch (declaration_node.getToken(self.tokens).?.kind) {
        .Var => .Var,
        .Const => .Const,
        else => unreachable,
    };

    const expr_type = try self.inferType(expr_node);
    var symbol_type: ?primitive.Type = null;
    const type_identifier_token = type_identifier_node.getToken(self.tokens);
    if (type_identifier_token) |token| {
        const type_name = token.getName(self.buffer);
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

    if (symbol_type.?.toInt() != expr_type.toInt()) {
        core.rprint("Error: Type mismatch in declaration of '{s}': expected {any}, got {any}\n", .{name, symbol_type, expr_type});
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
    for (node.children.items) |child| {
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
    _ = self;
    _ = node;
    return .DebugVal;
    // return switch (node.kind) {
    //     .Identifier => {
    //         const name = node.getToken(self.tokens).?.getName(self.buffer);
    //         if (self.isInScope(name)) |scope_map| {
    //             const decl = scope_map.get(name).?;
    //             return decl.symbol_type;
    //         } else {
    //             return error.UndefinedIdentifier;
    //         }
    //     },
    //     .Expression => {},
    //     .BinaryOperator, .UnaryOperator => .;
    //     ,
    //     // Add more cases for literals, function calls, etc.
    //     else => return error.UnknownType,
    // }
}

fn printAst(self: *Semantic) void {
    for (self.ast.items) |node| {
        self.printAstNode(node, 0);
    }
}

fn printAstNode(self: *Semantic, node: Node, depth: usize) void {
    var indent_buf: [32]u8 = undefined;
    const indent = indent_buf[0..@min(depth * 2, indent_buf.len)];
    for (indent) |*c| c.* = ' ';

    if (node.token_index) |token_index| {
        const token = self.tokens[token_index];
        const token_text = self.buffer[token.start..token.end];
        core.dprint("{s}{any} (token_index={d}) (token_kind={any}) (token_text=\"{s}\")\n", .{ indent, node.kind, token_index, token.kind, token_text });
    } else {
        core.dprint("{s}{any} (token_index=null)\n", .{ indent, node.kind });
    }

    for (node.children.items) |child| {
        self.printAstNode(child, depth + 1);
    }
}
