const std = @import("std");
const exit = @import("exit.zig");

const Token = @import("tokenizer.zig").Token;

const Parser = @This();
allocator: std.mem.Allocator,
tokens: []const Token,
buffer: []const u8,
current: usize,
ast: std.ArrayList(Node),

pub const Node = struct {
    kind: Kind,
    children: std.ArrayList(Node),
    token_index: ?usize = null,

    const Kind = enum {
        KEYWORD,
        IDENTIFIER,
        TYPE_IDENTIFIER,
        DECLARATION,
        IDK_YET,
        EXPRESSION,
    };
};

pub const Error = error{
    UnexpectedToken,

    OutOfMemory,
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

pub fn parse(self: *Parser) Error!void {
    // TODO: add bounds checking
    try self.ast.ensureTotalCapacity(self.allocator, 16);
    while (self.current < self.tokens.len) {
        const token = self.tokens[self.current];
        std.debug.print("Outer Token: {any} - {s}\n", .{ token.kind, self.buffer[token.start..token.end] });

        var maybe_node: ?Node = null;
        switch (token.kind) {
            .CONST, .VAR => {
                maybe_node = try self.parseDeclaration();
            },
            else => {
                std.debug.print("Unexpected token kind {any}\n", .{token.kind});
                exit.normal(201);
            },
        }
        if (maybe_node) |node| {
            try self.ast.append(self.allocator, node);
        } else {
            exit.normal(202);
        }
    }
}

fn parseDeclaration(self: *Parser) !Node {
    const declaration_token_index = self.current;
    _ = try self.consumeOneOf(.{ .CONST, .VAR });
    const name_identifier_index = self.current;
    _ = try self.consumeToken(.IDENTIFIER);

    var type_identifier_index: ?usize = null;
    var expr_node: Node = undefined;
    const curr = try self.currentOneOf(.{ .COLON, .COLON_EQUALS, .EQUALS });
    var assignemnt_kind = curr.kind;

    if (curr.kind == .COLON) {
        _ = try self.consumeToken(.COLON);
        type_identifier_index = self.current;
        _ = try self.consumeToken(.IDENTIFIER);
        assignemnt_kind = self.tokens[self.current].kind;
    }

    if (assignemnt_kind == .COLON_EQUALS or assignemnt_kind == .EQUALS) {
        _ = try self.consumeToken(assignemnt_kind);
        expr_node = try self.parseExpression();
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

fn consumeToken(self: *Parser, kind: Token.Kind) Error!Token {
    const token = self.tokens[self.current];
    if (token.kind != kind) {
        std.debug.print("Expected token kind to be one of {any}, found {any}\n", .{ kind, token.kind });
        return Error.UnexpectedToken;
    }
    self.current += 1;
    return token;
}

fn consumeOneOf(self: *Parser, comptime kinds: anytype) Error!Token {
    const token = self.tokens[self.current];
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            self.current += 1;
            return token;
        }
    }
    std.debug.print("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

fn currentOneOf(self: *Parser, comptime kinds: anytype) Error!Token {
    const token = self.tokens[self.current];
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    std.debug.print("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

inline fn consumeUnchecked(self: *Parser) Token {
    self.current += 1;
    return self.tokens[self.current - 1];
}

fn parseExpression(self: *Parser) !Node {
    return try self.parseExpressionWithPrecedence(Token.Precedence.LOWEST);
}

fn parseExpressionWithPrecedence(self: *Parser, precedence: Token.Precedence) Error!Node {
    var left = try self.parsePrefix();

    while (self.current < self.tokens.len and precedence.toInt() < self.tokens[self.current].getPrecedence().toInt()) {
        left = try self.parseInfixOrSuffix(left);
    }

    return left;
}

fn parsePrefix(self: *Parser) !Node {
    const token = self.tokens[self.current];
    switch (token.kind) {
        .NUMBER_LITERAL, .IDENTIFIER => {
            self.current += 1;
            return Node{
                .kind = .EXPRESSION,
                .children = .empty,
                .token_index = self.current - 1,
            };
        },
        .PAREND_LEFT => {
            self.current += 1;
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.LOWEST);
            _ = try self.consumeToken(.PAREND_RIGHT);

            var children: std.ArrayList(Node) = try .initCapacity(self.allocator, 1);
            try children.append(self.allocator, expr);

            return Node{
                .kind = .EXPRESSION,
                .children = children,
                .token_index = self.current - 1,
            };
        },
        .MINUS => {
            self.current += 1;
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.PREFIX);

            var children: std.ArrayList(Node) = try .initCapacity(self.allocator, 1);
            try children.append(self.allocator, expr);

            return Node{
                .kind = .EXPRESSION,
                .children = children,
                .token_index = self.current - 1,
            };
        },
        else => {
            std.debug.print("Unexpected token in parsePrefix: {any}\n", .{token.kind});
            return Error.UnexpectedToken;
        },
    }
}

fn parseInfixOrSuffix(self: *Parser, left: Node) !Node {
    const token = self.tokens[self.current];
    switch (token.kind) {
        .PLUS, .MINUS, .STAR, .SLASH => {
            const precedence = token.getPrecedence();
            const token_index = self.current;
            self.current += 1;
            const right = try self.parseExpressionWithPrecedence(precedence);

            var children: std.ArrayList(Node) = try .initCapacity(self.allocator, 2);
            try children.append(self.allocator, left);
            try children.append(self.allocator, right);

            return Node{
                .kind = .EXPRESSION,
                .children = children,
                .token_index = token_index,
            };
        },
        // .PAREND_LEFT => {
        //     self.current += 1;
        //     _ = try self.consumeToken(.PAREND_RIGHT);

        //     var children: std.ArrayList(Node) = try .initCapacity(self.allocator, 1);
        //     try children.append(self.allocator, left);

        //     return Node{
        //         .kind = .EXPRESSION,
        //         .children = children,
        //         .token_index = token_index,
        //     };
        // },
        else => {
            return left;
        },
    }
}
