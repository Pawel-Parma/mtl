const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");
const Node = @import("node.zig");

const Parser = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
tokens: []const Token,
current: usize,
ast: std.ArrayList(Node),
// TODO: refactor
// TODO: add nice error messages, everywhere

pub const Error = error{
    UnexpectedToken,
} || std.mem.Allocator.Error;

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
    const initialCapacity = @min(512, self.tokens.len / 2);
    try self.ast.ensureTotalCapacity(self.allocator, initialCapacity);
    while (!self.isAtEnd()) {
        const node = try self.parseNode();
        try self.ast.append(self.allocator, node);
    }
    self.printAst();
}

fn parseNode(self: *Parser) Error!Node {
    const token = self.peek();
    return switch (token.kind) {
        .Const, .Var => try self.parseDeclaration(),
        .CurlyLeft => try self.parseBlock(),
        else => self.unsupportedToken(),
    };
}

inline fn advance(self: *Parser) void {
    self.current += 1;
}

inline fn peek(self: *Parser) Token {
    return self.tokens[self.current];
}

inline fn isAtEnd(self: *Parser) bool { // TODO: put before unnesecery expects
    return self.current >= self.tokens.len;
}

inline fn currentOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.peek();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

inline fn expect(self: *Parser, kind: Token.Kind) !Token {
    const token = self.peek();
    if (token.kind != kind) {
        core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kind, token.kind });
        return Error.UnexpectedToken;
    }
    self.advance();
    return token;
}

inline fn consumeOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.peek();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            self.advance();
            return token;
        }
    }
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

inline fn ArrayListFromTuple(self: *Parser, tuple: anytype) !std.ArrayList(Node) {
    var list: std.ArrayList(Node) = try .initCapacity(self.allocator, tuple.len);
    inline for (tuple) |item| {
        try list.append(self.allocator, item);
    }
    return list;
}

fn parseDeclaration(self: *Parser) !Node {
    const declaration_token_index = self.current;
    const declaration_token = try self.consumeOneOf(.{ .Const, .Var });
    const name_identifier_index = self.current;
    _ = try self.expect(.Identifier);

    var type_identifier_index: ?usize = null;
    var expr_node: Node = undefined;
    const curr = try self.currentOneOf(.{ .Colon, .ColonEquals, .Equals });
    var assignment_kind = curr.kind;

    if (curr.kind == .Colon) {
        _ = try self.expect(.Colon);
        type_identifier_index = self.current;
        _ = try self.expect(.Identifier);
        assignment_kind = self.peek().kind;
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
        _ = try self.expect(assignment_kind);
        expr_node = try self.parseExpression();
        _ = try self.expect(.Semicolon);
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

fn parseBlock(self: *Parser) Error!Node {
    _ = try self.expect(.CurlyLeft);
    var statements: std.ArrayList(Node) = try .initCapacity(self.allocator, 16);
    while (self.peek().kind != .CurlyRight) {
        const node = try self.parseNode();
        try statements.append(self.allocator, node);
    }
    _ = try self.expect(.CurlyRight);

    return Node{
        .kind = .Scope,
        .children = statements,
    };
}

inline fn parseExpression(self: *Parser) !Node {
    return try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
}

fn parseExpressionWithPrecedence(self: *Parser, precedence: Token.Precedence) Error!Node {
    var left = try self.parsePrefix();

    while (precedence.toInt() < self.peek().precedence().toInt()) {
        left = try self.parseInfixOrSuffix(left);
    }

    return left;
}

fn parsePrefix(self: *Parser) !Node {
    const token = self.peek();
    const token_index = self.current;
    self.advance();
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
            _ = try self.expect(.ParenRight);
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
    const token = self.peek();
    const token_index = self.current;
    self.advance();
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

fn unsupportedToken(self: *Parser) noreturn {
    const token = self.peek();
    core.rprint("Unexpected token kind {any}\n", .{token.kind});
    core.exit(201);
}

fn printAst(self: *Parser) void {
    core.dprint("AST:\n", .{});
    for (self.ast.items) |node| {
        self.printAstNode(node, 0);
    }
    core.dprint("\n", .{});
}

fn printAstNode(self: *Parser, node: Node, depth: usize) void {
    var indent_buf: [32]u8 = undefined;
    const indent = indent_buf[0..@min(depth * 2, indent_buf.len)];
    for (indent) |*c| c.* = ' ';

    const token = node.token(self.tokens);
    if (token) |t| {
        core.dprint("{s}{any} (token_index={d}) (token.kind={any}) (token.text=\"{s}\")\n", .{ indent, node.kind, node.token_index.?, t.kind, t.string(self.buffer) });
    } else {
        core.dprint("{s}{any} (token_index=null)\n", .{ indent, node.kind });
    }

    for (node.children.items) |child| {
        self.printAstNode(child, depth + 1);
    }
}
