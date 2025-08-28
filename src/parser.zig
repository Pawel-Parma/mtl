const std = @import("std");
const core = @import("core.zig");


const Token = @import("tokenizer.zig").Token;


const Parser = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
tokens: []const Token,
current: usize,
ast: Node.List,

pub const Node = struct {
    kind: Kind,
    children: List,
    token_index: ?usize = null,
    
    const Kind = enum {
        KEYWORD,
        IDENTIFIER,
        TYPE_IDENTIFIER,
        DECLARATION,
        EXPRESSION,
        BINARY_EXPRESSION,
        UNARY_EXPRESSION,
        BLOCK,
    };

    pub const List = std.ArrayList(Node);

    pub inline fn getToken(self: *const Node, tokens: []const Token) ?Token {
        return tokens[self.token_index.?];
    }
};

pub const Error = error{
    UnexpectedToken,

    OutOfMemory,
};

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, tokens: []const Token) Parser {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .tokens = tokens,
        .current = 0,
        .ast = .empty,
    };
}

pub fn deinit(self: *Parser) !void {
    while (self.ast.items.len > 0) {
        var node = self.ast.pop().?;
        for (node.children.items) |child| {
            try self.ast.append(self.allocator, child);
        }
        node.children.deinit(self.allocator);
    }
}

pub fn parse(self: *Parser) Error!void {
    core.dprint("\nTokens:\n", .{});
    try self.ast.ensureTotalCapacity(self.allocator, 16);
    while (self.current < self.tokens.len) {
        const node: Node = try self.parseNode();
        try self.ast.append(self.allocator, node);
    }
}

fn parseNode(self: *Parser) !Node {
    const token = self.currentToken();
    return switch (token.kind) {
        .CONST, .VAR => try self.parseDeclaration(),
        .CURLY_LEFT => try self.parseBlock(),
        else => {
            core.rprint("Unexpected token kind {any}\n", .{token.kind});
            core.exit(201);
        },
    };
}

fn currentToken(self: *Parser) Token {
    if (self.current < self.tokens.len) {
        const token = self.tokens[self.current];
        core.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, token.getName(self.buffer) });
        return token;
    }
    core.rprint("Attempted to access current token out of bounds: {d} >= {d}\n", .{ self.current, self.tokens.len });
    core.exit(203);
}

fn currentOneOf(self: *Parser, comptime kinds: anytype) Error!Token {
    const token = self.currentToken();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}
fn consumeToken(self: *Parser, kind: Token.Kind) Error!Token {
    const token = self.currentToken();
    if (token.kind != kind) {
        core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kind, token.kind });
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
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
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

fn parseBlock(self: *Parser) Error!Node {
    _ = try self.consumeToken(.CURLY_LEFT);
    var statements: Node.List = try .initCapacity(self.allocator, 16);
    while (self.currentToken().kind != .CURLY_RIGHT) {
        const node = try self.parseNode();
        try statements.append(self.allocator, node);
    }
    _ = try self.consumeToken(.CURLY_RIGHT);

    return Node{
        .kind = .BLOCK,
        .children = statements,
    };
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
            core.rprint("Unexpected token in parsePrefix: {any}\n", .{token.kind});
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

inline fn ArrayListFromTuple(self: *Parser, tuple: anytype) !Node.List {
    var list: Node.List = try .initCapacity(self.allocator, tuple.len);
    inline for (tuple) |item| {
        try list.append(self.allocator, item);
    }
    return list;
}
