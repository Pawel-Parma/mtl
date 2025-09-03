const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");

const Parser = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
tokens: []const Token,
current: usize,
ast: Node.List,
// TODO: refactor
// TODO: add nice error messages, everywhere

pub const Node = struct {
    kind: Kind,
    children: List,
    token_index: ?usize = null,

    const Kind = enum {
        Keyword,
        Identifier,
        TypeIdentifier,
        Declaration,
        Expression,
        BinaryOperator,
        UnaryOperator,
        NumberLiteral,
        Scope,
    };

    pub const List = std.ArrayList(Node);

    pub inline fn getToken(self: *const Node, tokens: []const Token) ?Token {
        if (self.token_index) |idx| {
            return tokens[idx];
        } else {
            return null;
        }
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

fn parseNode(self: *Parser) Error!Node {
    const token = self.currentToken();
    return switch (token.kind) {
        .Const, .Var => try self.parseDeclaration(),
        .CurlyLeft => try self.parseBlock(),
        else => self.unsupportedToken(),
    };
}

inline fn currentToken(self: *Parser) Token {
    if (self.current < self.tokens.len) {
        const token = self.tokens[self.current];
        core.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, token.string(self.buffer) });
        return token;
    }
    core.rprint("Attempted to access current token out of bounds: {d} >= {d}\n", .{ self.current, self.tokens.len });
    core.exit(203);
}

inline fn currentOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.currentToken();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}
inline fn consumeToken(self: *Parser, kind: Token.Kind) !Token {
    const token = self.currentToken();
    if (token.kind != kind) {
        core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kind, token.kind });
        return Error.UnexpectedToken;
    }
    self.current += 1;
    return token;
}

inline fn consumeOneOf(self: *Parser, comptime kinds: anytype) !Token {
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

inline fn parseDeclaration(self: *Parser) !Node {
    const declaration_token_index = self.current;
    const declaration_token = try self.consumeOneOf(.{ .Const, .Var });
    const name_identifier_index = self.current;
    _ = try self.consumeToken(.Identifier);

    var type_identifier_index: ?usize = null;
    var expr_node: Node = undefined;
    const curr = try self.currentOneOf(.{ .Colon, .ColonEquals, .Equals });
    var assignment_kind = curr.kind;

    if (curr.kind == .Colon) {
        _ = try self.consumeToken(.Colon);
        type_identifier_index = self.current;
        _ = try self.consumeToken(.Identifier);
        assignment_kind = self.currentToken().kind;
    }

    if (declaration_token.kind == .Var and curr.kind == .Equals and assignment_kind == .Equals) {
        core.rprint("Error: 'var' declarations must use ':=' for assignment when omitting type, not '='\n", .{});
        return Error.UnexpectedToken;
    }

    if (declaration_token.kind == .Const and assignment_kind == .ColonEquals) {
        core.rprint("Error: 'const' declarations must use '=' for assignment when omitting type, not ':='\n", .{});
        return Error.UnexpectedToken;
    }

    if (assignment_kind == .ColonEquals or assignment_kind == .Equals) {
        _ = try self.consumeToken(assignment_kind);
        expr_node = try self.parseExpression();
        _ = try self.consumeToken(.Semicolon);
    }

    const children = try self.ArrayListFromTuple(.{
        Node{ .kind = .Keyword, .children = .empty, .token_index = declaration_token_index },
        Node{ .kind = .Identifier, .children = .empty, .token_index = name_identifier_index },
        Node{ .kind = .TypeIdentifier, .children = .empty, .token_index = type_identifier_index },
        expr_node,
    });

    return Node{
        .kind = .Declaration,
        .children = children,
    };
}

inline fn parseBlock(self: *Parser) Error!Node {
    _ = try self.consumeToken(.CurlyLeft);
    var statements: Node.List = try .initCapacity(self.allocator, 16);
    while (self.currentToken().kind != .CurlyRight) {
        const node = try self.parseNode();
        try statements.append(self.allocator, node);
    }
    _ = try self.consumeToken(.CurlyRight);

    return Node{
        .kind = .Scope,
        .children = statements,
    };
}

inline fn unsupportedToken(self: *Parser) noreturn {
    const token = self.currentToken();
    core.rprint("Unexpected token kind {any}\n", .{token.kind});
    core.exit(201);
}

inline fn parseExpression(self: *Parser) !Node {
    return try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
}

fn parseExpressionWithPrecedence(self: *Parser, precedence: Token.Precedence) Error!Node {
    var left = try self.parsePrefix();

    while (precedence.toInt() < self.currentToken().precedence().toInt()) {
        left = try self.parseInfixOrSuffix(left);
    }

    return left;
}

fn parsePrefix(self: *Parser) !Node {
    const token = self.currentToken();
    const token_index = self.current;
    self.current += 1;
    switch (token.kind) {
        .IntLiteral, .FloatLiteral, .Identifier => {
            return Node{
                .kind = .NumberLiteral,
                .children = .empty,
                .token_index = token_index,
            };
        },
        .ParenLeft => {
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
            _ = try self.consumeToken(.ParenRight);
            const children = try self.ArrayListFromTuple(.{expr});
            return Node{
                .kind = .Expression,
                .children = children,
                .token_index = token_index,
            };
        },
        .Minus => {
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.Prefix);
            const children = try self.ArrayListFromTuple(.{expr});
            return Node{
                .kind = .UnaryOperator,
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
        .Plus, .Minus, .Star, .Slash => {
            const right = try self.parseExpressionWithPrecedence(token.precedence());
            const children = try self.ArrayListFromTuple(.{ left, right });
            return Node{
                .kind = .BinaryOperator,
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
