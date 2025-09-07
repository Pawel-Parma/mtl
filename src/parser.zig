const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");
const Node = @import("node.zig");

const Parser = @This();
arena: std.heap.ArenaAllocator,
buffer: []const u8,
file_path: []const u8,
tokens: []const Token,
current: usize,
success: bool,
ast: std.ArrayList(Node),

pub const Error = error{
    UnexpectedToken,
    UnexpectedEof,
    ParsingFailed,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, file_path: []const u8, tokens: []const Token) Parser {
    return .{
        .arena = .init(allocator),
        .buffer = buffer,
        .file_path = file_path,
        .tokens = tokens,
        .current = 0,
        .success = true,
        .ast = .empty,
    };
}

pub fn deinit(self: *Parser) void {
    self.arena.deinit();
}

pub fn parse(self: *Parser) Error!void {
    const allocator = self.arena.allocator();
    const initialCapacity = @min(512, self.tokens.len / 2);
    try self.ast.ensureTotalCapacity(allocator, initialCapacity);
    while (!self.isAtEnd()) {
        const node = self.parseNode() catch {
            self.synchronize();
            continue;
        };
        try self.ast.append(allocator, node);
    }
    if (!self.success) {
        return Error.ParsingFailed;
    }
    self.printAst();
}

fn parseNode(self: *Parser) Error!Node {
    try self.checkEof();
    const token = self.peek();
    return switch (token.kind) {
        .Const, .Var => try self.parseDeclaration(),
        .CurlyLeft => try self.parseBlock(),
        else => self.reportError("Expected statement\n", .{}),
    };
}

inline fn advance(self: *Parser) usize {
    self.current += 1;
    return self.current - 1;
}

inline fn isAtEnd(self: *Parser) bool {
    return self.current >= self.tokens.len;
}

fn checkEof(self: *Parser) !void {
    if (self.isAtEnd()) {
        self.reportError("Unexpected end of file\n", .{}) catch {};
        return Error.UnexpectedEof;
    }
}

inline fn peek(self: *Parser) Token {
    return self.tokens[self.current];
}

fn match(self: *Parser, comptime kinds: anytype) !Token {
    try self.checkEof();
    const token = self.peek();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            return token;
        }
    }
    return self.reportError("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
}

fn expectOneOf(self: *Parser, comptime kinds: anytype) !Token {
    const token = try self.match(kinds);
    _ = self.advance();
    return token;
}

fn expect(self: *Parser, comptime kind: Token.Kind) !Token {
    return self.expectOneOf(.{kind});
}

fn synchronize(self: *Parser) void {
    while (!self.isAtEnd() and !(self.peek().kind == .Eol or self.peek().kind == .CurlyRight)) {
        _ = self.advance();
    }
    if (!self.isAtEnd() and (self.peek().kind == .Eol or self.peek().kind == .CurlyRight)) {
        _ = self.advance();
    }
}

inline fn makeLeaf(kind: Node.Kind, token_index: ?usize) Node {
    return Node{ .kind = kind, .children = &.{}, .token_index = token_index };
}

inline fn nodesFromTuple(self: *Parser, tuple: anytype) ![]Node {
    const nodeList = try self.arena.allocator().alloc(Node, tuple.len);
    inline for (tuple, 0..) |item, i| {
        nodeList[i] = item;
    }
    return nodeList;
}

fn reportError(self: *Parser, comptime fmt: []const u8, args: anytype) error{UnexpectedToken} {
    self.success = false;
    const len = self.buffer.len;
    const token = if (self.isAtEnd()) Token{ .kind = .Invalid, .start = len, .end = len } else self.peek();

    const line_info = token.lineInfo(self.buffer);
    const column_number = token.start - line_info.start;
    const line = core.getLine(self.buffer, line_info.start, token.start, len);

    core.printSourceLine(fmt, args, self.file_path, line_info.number, column_number, line, token.len());
    return error.UnexpectedToken;
}

fn parseDeclaration(self: *Parser) !Node {
    const declaration = try self.expectOneOf(.{ .Var, .Const });
    const name_identifier_index = self.current;
    _ = try self.expect(.Identifier);

    var type_identifier_index: ?usize = null;
    const token = switch (declaration.kind) {
        .Const => try self.expectOneOf(.{ .Colon, .Equals }),
        .Var => try self.expectOneOf(.{ .Colon, .ColonEquals }),
        else => unreachable,
    };
    if (token.kind == .Colon) {
        type_identifier_index = self.current;
        _ = try self.expect(.Identifier);
        _ = try self.expect(.Equals);
    }
    const expr_node = try self.parseExpression();
    _ = try self.expect(.Eol);

    const children = try self.nodesFromTuple(.{
        makeLeaf(.Identifier, name_identifier_index),
        makeLeaf(.TypeIdentifier, type_identifier_index),
        expr_node,
    });

    const kind: Node.Kind = switch (declaration.kind) {
        .Const => .ConstDeclaration,
        .Var => .VarDeclaration,
        else => unreachable,
    };
    return Node{ .kind = kind, .children = children };
}

fn parseBlock(self: *Parser) Error!Node {
    _ = try self.expect(.CurlyLeft);
    const statements = try self.parseNodesUntil(.CurlyRight);
    _ = try self.expect(.CurlyRight);
    return Node{ .kind = .Scope, .children = statements };
}

fn parseNodesUntil(self: *Parser, endKind: Token.Kind) ![]Node {
    var list: std.ArrayList(Node) = .empty;
    while (!self.isAtEnd() and self.peek().kind != endKind) {
        const node = self.parseNode() catch {
            self.synchronize();
            continue;
        };
        try list.append(self.arena.allocator(), node);
    }
    return try list.toOwnedSlice(self.arena.allocator());
}

inline fn parseExpression(self: *Parser) !Node {
    // TODO: handle associativity
    return self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
}

fn parseExpressionWithPrecedence(self: *Parser, precedence: Token.Precedence) Error!Node {
    var left = try self.parsePrefix();
    while (!self.isAtEnd() and precedence.toInt() < self.peek().precedence().toInt()) {
        left = try self.parseInfixOrSuffix(left);
    }
    return left;
}

fn parsePrefix(self: *Parser) !Node {
    try self.checkEof();
    const token = self.peek();
    switch (token.kind) {
        .Identifier => return makeLeaf(.Identifier, self.advance()),
        .IntLiteral, .FloatLiteral => return makeLeaf(.NumberLiteral, self.advance()),
        .ParenLeft => {
            const token_index = self.advance();
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
            _ = try self.expect(.ParenRight);
            const children = try self.nodesFromTuple(.{expr});
            return .{ .kind = .Expression, .children = children, .token_index = token_index };
        },
        .Minus => {
            const token_index = self.advance();
            const expr = try self.parseExpressionWithPrecedence(Token.Precedence.Prefix);
            const children = try self.nodesFromTuple(.{expr});
            return .{ .kind = .UnaryOperator, .children = children, .token_index = token_index };
        },
        else => return self.reportError("Unexpected prefix: {any}\n", .{token.kind}),
    }
}

fn parseInfixOrSuffix(self: *Parser, left: Node) !Node {
    const token = self.peek();
    const token_index = self.advance();
    switch (token.kind) {
        .Plus, .Minus, .Star, .Slash => {
            const right = try self.parseExpressionWithPrecedence(token.precedence());
            const children = try self.nodesFromTuple(.{ left, right });
            return Node{ .kind = .BinaryOperator, .children = children, .token_index = token_index };
        },
        else => return self.reportError("Unexpected infixOrSuffix: {any}\n", .{token.kind}),
    }
}

fn printAst(self: *Parser) void {
    core.dprint("AST:\n", .{});
    for (self.ast.items) |node| {
        self.printAstNode(node, 0);
    }
    core.dprint("\n", .{});
}

fn printAstNode(self: *Parser, node: Node, depth: usize) void {
    for (0..depth) |_| {
        core.dprint("  ", .{});
    }
    core.dprint("{any} (token_index={any})", .{ node.kind, node.token_index });
    const token = node.token(self.tokens);
    if (token) |t| {
        core.dprint(" (token.kind={any}) (token.string=\"{s}\")", .{ t.kind, t.string(self.buffer) });
    }
    core.dprint("\n", .{});

    for (node.children) |child| {
        self.printAstNode(child, depth + 1);
    }
}
