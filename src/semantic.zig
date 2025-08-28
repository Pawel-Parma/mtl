const std = @import("std");
const core = @import("core.zig");

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
    symbol_type: ?Node,
    expr: ?Node,

    pub const Kind = enum {
        VAR,
        CONST,
    };
};

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

    for (self.ast.items) |node| {
        try self.semanticPass(node, 0);
    }
    return;
}

fn semanticPass(self: *Semantic, node: Node, depth: usize) !void {
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
        .DECLARATION => {
            const declaration = node.children.items[0];
            const identifier = node.children.items[1];
            const type_identifier = node.children.items[2];
            const expr = node.children.items[3];

            const name = identifier.getToken(self.tokens).?.getName(self.buffer);
            var current_scope = &self.scopes.items[self.scopes.items.len - 1];
            var i = self.scopes.items.len;
            while (i > 1) : (i -= 1) {
                if (self.scopes.items[i - 2].contains(name)) {
                    core.rprint("Error: Shadowing of '{s}' from outer scope is not allowed\n", .{name});
                    core.exit(11);
                }
            }

            const kind: Declaration.Kind = switch (declaration.getToken(self.tokens).?.kind) {
                .VAR => .VAR,
                .CONST => .CONST,
                else => unreachable,
            };

            try current_scope.put(name, .{
                .kind = kind,
                .symbol_type = type_identifier,
                .expr = expr,
            });
        },
        .BLOCK => {
            try self.scopes.append(self.allocator, .init(self.allocator));
            for (node.children.items) |child| {
                try self.semanticPass(child, depth + 1);
            }
            var scope = self.scopes.pop().?;
            scope.deinit();
        },
        else => {
            core.rprint("{s}Unhandled node kind {any}\n", .{ indent, node.kind });
            core.exit(99);
        },
    }
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
