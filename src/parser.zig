const std = @import("std");
const exit = @import("exit.zig");

const Token = @import("tokenizer.zig").Token;

const Parser = @This();
allocator: std.mem.Allocator,
tokens: []const Token,
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
        EXPRESSION,
        BINARY_EXPRESSION,
        UNARY_EXPRESSION,
    };
};

pub const Error = error{
    UnexpectedToken,

    OutOfMemory,
};

pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
    return .{
        .allocator = allocator,
        .tokens = tokens,
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
        const token = self.currentToken();
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
            std.debug.print("Parser returned null node unexpectedly\n", .{});
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
        assignemnt_kind = self.currentToken().kind;
    }

    if (assignemnt_kind == .COLON_EQUALS or assignemnt_kind == .EQUALS) {
        _ = try self.consumeToken(assignemnt_kind);
        expr_node = try self.parseExpression();
        _ = try self.consumeToken(.SEMICOLON);
    }

    const children = try self.ArrayListFromTuple(.{
        Node{ .kind = .KEYWORD, .children = .empty, .token_index = declaration_token_index },
        Node{ .kind = .IDENTIFIER, .children = .empty, .token_index = name_identifier_index },
        Node{ .kind = .TYPE_IDENTIFIER, .children = .empty, .token_index = type_identifier_index },
        expr_node,
    });

    return Node{
        .kind = .DECLARATION,
        .children = children,
    };
}

fn consumeToken(self: *Parser, kind: Token.Kind) Error!Token {
    const token = self.currentToken();
    if (token.kind != kind) {
        std.debug.print("Expected token kind to be one of {any}, found {any}\n", .{ kind, token.kind });
        return Error.UnexpectedToken;
    }
    self.current += 1;
    return token;
}

fn consumeOneOf(self: *Parser, comptime kinds: anytype) Error!Token {
    const token = self.currentToken();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            self.current += 1;
            return token;
        }
    }
    std.debug.print("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

fn currentToken(self: *Parser) Token {
    if (self.current < self.tokens.len) {
        return self.tokens[self.current];
    }
    std.debug.print("Attempted to access current token out of bounds: {d} >= {d}\n", .{ self.current, self.tokens.len });
    exit.normal(203);
}

fn currentOneOf(self: *Parser, comptime kinds: anytype) Error!Token {
    const token = self.currentToken();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    std.debug.print("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

fn parseExpression(self: *Parser) !Node {
    return try self.parseExpressionWithPrecedence(Token.Precedence.LOWEST);
}

fn parseExpressionWithPrecedence(self: *Parser, precedence: Token.Precedence) Error!Node {
    var left = try self.parsePrefix();

    while (precedence.toInt() < self.currentToken().getPrecedence().toInt()) {
        left = try self.parseInfixOrSuffix(left);
    }

    return left;
}

fn parsePrefix(self: *Parser) !Node {
    const token = self.currentToken();
    const token_index = self.current;
    self.current += 1;
    switch (token.kind) {
        .NUMBER_LITERAL, .IDENTIFIER => {
            return Node{
                .kind = .EXPRESSION,
                .children = .empty,
                .token_index = token_index,
            };
        },
        .PAREND_LEFT => {
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.LOWEST);
            _ = try self.consumeToken(.PAREND_RIGHT);
            const children = try self.ArrayListFromTuple(.{expr});
            return Node{
                .kind = .EXPRESSION,
                .children = children,
                .token_index = token_index,
            };
        },
        .MINUS => {
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.PREFIX);
            const children = try self.ArrayListFromTuple(.{expr});
            return Node{
                .kind = .UNARY_EXPRESSION,
                .children = children,
                .token_index = token_index,
            };
        },
        else => {
            std.debug.print("Unexpected token in parsePrefix: {any}\n", .{token.kind});
            return Error.UnexpectedToken;
        },
    }
}

fn parseInfixOrSuffix(self: *Parser, left: Node) !Node {
    const token = self.currentToken();
    const token_index = self.current;
    self.current += 1;
    switch (token.kind) {
        .PLUS, .MINUS, .STAR, .SLASH => {
            const right = try self.parseExpressionWithPrecedence(token.getPrecedence());
            const children = try self.ArrayListFromTuple(.{ left, right });
            return Node{
                .kind = .BINARY_EXPRESSION,
                .children = children,
                .token_index = token_index,
            };
        },
        else => {
            return left;
        },
    }
}

inline fn ArrayListFromTuple(self: *Parser, tuple: anytype) !std.ArrayList(Node) {
    var list: std.ArrayList(Node) = try .initCapacity(self.allocator, tuple.len);
    inline for (tuple) |item| {
        try list.append(self.allocator, item);
    }
    return list;
}
