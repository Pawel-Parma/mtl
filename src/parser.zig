const std = @import("std");
const exit = @import("exit.zig").exit;

const Token = @import("tokenizer.zig").Token;

const Parser = @This();
allocator: std.mem.Allocator,
tokens: []const Token,
buffer: []const u8,
current: usize,
ast: std.ArrayList(Node),

const Node = struct {
    kind: Kind,
    children: std.ArrayList(Node),
    token_index: ?usize = null,

    const Kind = enum {
        TOP_LEVEL,
        KEYWORD,
        IDENTIFIER,
        TYPE_IDENTIFIER,
        DECLARATION,
        IDK_YET,
        EXPRESSION,
    };
};

pub fn init(allocator: std.mem.Allocator, tokens: []const Token, buffer: []const u8) Parser {
    return .{
        .allocator = allocator,
        .tokens = tokens,
        .buffer = buffer,
        .current = 0,
        .ast = .empty,
    };
}

pub fn deinit(self: *Parser) !void {
    while (self.ast.items.len > 0) {
        var node = &self.ast.items[self.ast.items.len - 1];
        if (node.children.items.len != 0) {
            for (node.children.items) |child| {
                try self.ast.append(self.allocator, child);
            }
            node.children = .empty;
        } else {
            _ = self.ast.pop();
            node.children.deinit(self.allocator);
        }
    }
}

pub fn parse(self: *Parser) !void {
    for (self.tokens) |token| {
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
    }
    std.debug.print("\n", .{});

    while (self.current < self.tokens.len) {
        const token = self.tokens[self.current];
        std.debug.print("Outer Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });

        var maybe_node: ?Node = null;
        switch (token.kind) {
            .CONST, .VAR => {
                maybe_node = try self.parseDeclaration();
            },
            else => {
                std.debug.print("Unexpected token of kind {s}\n", .{@tagName(token.kind)});
                exit(201);
            },
        }
        if (maybe_node) |node| {
            try self.ast.append(self.allocator, node);
        } else {
            exit(202);
        }
    }
}

fn parseDeclaration(self: *Parser) !Node {
    const declaration_token_index = self.current;
    _ = try self.consumeOneOf(.{ .CONST, .VAR });
    const name_identifier_index = self.current;
    var token = self.tokens[self.current];
    std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
    _ = try self.consumeToken(.IDENTIFIER);

    var type_identifier_index: ?usize = null;
    var expr_node: Node = undefined;
    const curr = try self.currentOneOf(.{ .COLON, .COLON_EQUALS, .EQUALS });
    var curr_kind = curr.kind;

    if (curr_kind == .COLON) {
        token = self.tokens[self.current];
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
        _ = try self.consumeToken(.COLON);
        type_identifier_index = self.current;
        token = self.tokens[self.current];
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
        _ = try self.consumeToken(.IDENTIFIER);
        curr_kind = self.tokens[self.current].kind;
    }

    if (curr_kind == .COLON_EQUALS) {
        token = self.tokens[self.current];
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
        _ = try self.consumeToken(curr_kind);
        expr_node = try self.parseExpression();
        token = self.tokens[self.current];
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
        _ = try self.consumeToken(.SEMICOLON);
    }

    if (curr_kind == .EQUALS) {
        token = self.tokens[self.current];
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
        _ = try self.consumeToken(curr_kind);
        expr_node = try self.parseExpression();
        token = self.tokens[self.current];
        std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });
        _ = try self.consumeToken(.SEMICOLON);
    }

    var children: std.ArrayList(Node) = try .initCapacity(self.allocator, 4);
    try children.append(self.allocator, .{ .kind = .KEYWORD, .children = .empty, .token_index = declaration_token_index });
    try children.append(self.allocator, .{ .kind = .IDENTIFIER, .children = .empty, .token_index = name_identifier_index });
    try children.append(self.allocator, .{ .kind = .TYPE_IDENTIFIER, .children = .empty, .token_index = type_identifier_index });
    try children.append(self.allocator, expr_node);

    return Node{
        .kind = .DECLARATION,
        .children = children,
    };
}

fn parseExpression(self: *Parser) !Node {
    // TODO: add logic for more complex expressions (pratt parser)
    const next_index = self.current;
    const token = self.tokens[self.current];
    std.debug.print("Token: {s} - {d} - {d} - {s}\n", .{ @tagName(token.kind), token.start, token.end, self.buffer[token.start..token.end] });

    _ = try self.consumeOneOf(.{ .NUMBER_LITERAL, .IDENTIFIER });

    var children: std.ArrayList(Node) = try .initCapacity(self.allocator, 1);
    try children.append(self.allocator, .{ .kind = .IDK_YET, .children = .empty, .token_index = next_index });

    return Node{
        .kind = .EXPRESSION,
        .children = children,
    };
}

fn consumeToken(self: *Parser, kind: Token.Kind) !Token {
    const token = self.tokens[self.current];
    if (token.kind != kind) {
        std.debug.print("Expected token of kind {s}, found {s}\n", .{ @tagName(kind), @tagName(token.kind) });
        return error.ExpectedToken;
    }
    self.current += 1;
    return token;
}

fn consumeOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.tokens[self.current];
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            self.current += 1;
            return token;
        }
    }
    std.debug.print("Expected one of the specified token kinds, found {s}\n", .{@tagName(token.kind)});
    return error.ExpectedToken;
}

fn currentOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.tokens[self.current];
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    std.debug.print("Expected one of the specified token kinds, found {s}\n", .{@tagName(token.kind)});
    return error.ExpectedToken;
}

inline fn consumeUnchecked(self: *Parser) Token {
    self.current += 1;
    return self.tokens[self.current - 1];
}
