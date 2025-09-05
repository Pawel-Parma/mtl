const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");
const Node = @import("node.zig");

const Parser = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
file_path: []const u8,
tokens: []const Token,
current: usize,
success_state: Error!void,
ast: std.ArrayList(Node),
// TODO: refactor
// TODO: add nice error messages, everywhere

pub const Error = error{
    UnexpectedToken,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, file_path: []const u8, tokens: []const Token) Parser {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .file_path = file_path,
        .tokens = tokens,
        .current = 0,
        .success_state = void{},
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
        const node = self.parseNode() catch continue;
        try self.ast.append(self.allocator, node);
    }
    if (self.success_state catch null != null) self.printAst();
    return self.success_state;
}

fn parseNode(self: *Parser) Error!Node {
    const token = self.peek();
    return switch (token.kind) {
        .Eol => blk: {
            _ = self.advance();
            break :blk self.parseNode();
        },
        .Const, .Var => try self.parseDeclaration(),
        .CurlyLeft => try self.parseBlock(),
        else => self.unexpectedToken(),
    };
}

inline fn advance(self: *Parser) usize {
    self.current += 1;
    return self.current - 1;
}

inline fn peek(self: *Parser) Token {
    if (self.isAtEnd()) {
        core.rprint("Unexpected end of input\n", .{});
        core.exit(200);
    }
    return self.tokens[self.current];
}

inline fn isAtEnd(self: *Parser) bool {
    return self.current >= self.tokens.len;
}

inline fn currentOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.peek();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    _ = self.unexpectedToken();
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
    return Error.UnexpectedToken;
}

inline fn expect(self: *Parser, kind: Token.Kind) !Token {
    const token = self.peek();
    if (token.kind == kind) {
        _ = self.advance();
        return token;
    }
    _ = self.unexpectedToken();
    core.rprint("Expected token kind to be one of {any}, found {any}\n", .{ kind, token.kind });
    return Error.UnexpectedToken;
}

inline fn consumeOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = self.peek();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            _ = self.advance();
            return token;
        }
    }
    _ = self.unexpectedToken();
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
        _ = self.unexpectedToken();
        core.rprint("Error: 'var' declarations must use ':=' for assignment when omitting type, not '='\n", .{});
        return Error.UnexpectedToken;
    }

    if (declaration_token.kind == .Const and assignment_kind == .ColonEquals) {
        _ = self.unexpectedToken();
        core.rprint("Error: 'const' declarations must use '=' for assignment when omitting type, not ':='\n", .{});
        return Error.UnexpectedToken;
    }

    if (assignment_kind == .ColonEquals or assignment_kind == .Equals) {
        _ = try self.expect(assignment_kind);
        expr_node = try self.parseExpression();
        _ = try self.expect(.Eol);
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
    return Node{ .kind = .Scope, .children = statements };
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
    const token_index = self.advance();
    switch (token.kind) {
        .Identifier => return .{ .kind = .Identifier, .children = .empty, .token_index = token_index },
        .IntLiteral, .FloatLiteral => return .{ .kind = .NumberLiteral, .children = .empty, .token_index = token_index },
        .ParenLeft => {
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
            _ = try self.expect(.ParenRight);
            const children = try self.ArrayListFromTuple(.{expr});
            return .{ .kind = .Expression, .children = children, .token_index = token_index };
        },
        .Minus => {
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.Prefix);
            const children = try self.ArrayListFromTuple(.{expr});
            return .{ .kind = .UnaryOperator, .children = children, .token_index = token_index };
        },
        else => {
            _ = self.unexpectedToken();
            core.rprint("Unexpected token in parsePrefix: {any}\n", .{token.kind});
            return Error.UnexpectedToken;
        },
    }
}

fn parseInfixOrSuffix(self: *Parser, left: Node) !Node {
    const token = self.peek();
    const token_index = self.advance();
    switch (token.kind) {
        .Plus, .Minus, .Star, .Slash => {
            const right = try self.parseExpressionWithPrecedence(token.precedence());
            const children = try self.ArrayListFromTuple(.{ left, right });
            return Node{ .kind = .BinaryOperator, .children = children, .token_index = token_index };
        },
        else => {
            return left;
        },
    }
}

fn unexpectedToken(self: *Parser) Node {
    self.success_state = Error.UnexpectedToken;
    const token = self.peek();

    var line_number: usize = 1;
    var line_start: usize = 0;
    for (self.buffer[0..token.start], 0..) |c, i| {
        if (c == '\n') {
            line_number += 1;
            line_start = i + 1;
        }
    }
    const column_number = token.start - line_start;
    const line_end = std.mem.indexOfScalarPos(u8, self.buffer, token.start, '\n') orelse self.buffer.len;
    const line = self.buffer[line_start..line_end];

    core.printSourceLine(
        "unexpected token",
        self.file_path,
        line_number,
        column_number,
        line,
        token.end - token.start,
    );
    while (!self.isAtEnd() and (self.peek().kind == .Eol or self.peek().kind == .CurlyRight)) {
        core.dprintn("Skping1");
        _ = self.advance();
    }
    if (!self.isAtEnd()) {
        core.dprintn("Skping1");
        _ = self.advance();
    }
    return .{ .kind = .Invalid, .children = .empty, .token_index = null };
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
