const std = @import("std");
// TODO: append statements directyl to list

const Printer = @import("printer.zig");
const File = @import("file.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");

const Parser = @This();
allocator: std.mem.Allocator,
printer: Printer,
file: *File,

pub const Error = error{
    UnexpectedToken,
    UnexpectedEof,
    ParsingFailed,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, printer: Printer, file: *File) Parser {
    return .{
        .allocator = allocator,
        .printer = printer,
        .file = file,
    };
}

pub fn parse(self: *Parser) Error!void {
    try self.file.ensureAstCapacity();
    while (!self.isAtEnd()) {
        self.parseNode() catch {
            self.synchronize();
        };
    }
    if (!self.file.success) {
        return Error.ParsingFailed;
    }
    self.file.printAst();
}

fn parseNode(self: *Parser) Error!void {
    const token = self.peek();
    return switch (token.kind) {
        .Const, .Var => try self.parseDeclaration(),
        .CurlyLeft => try self.parseBlock(),
        .Fn => try self.parseFunction(),
        .Return => try self.parseReturn(),
        .Identifier => try self.parseIdentifier(), // TODO: find more elegant sollution
        else => self.reportError("Expected statement\n", .{}),
    };
}

inline fn advance(self: *Parser) u32 {
    self.file.current += 1;
    return self.file.current - 1;
}

inline fn peek(self: *Parser) Token {
    return self.file.tokens.items[self.file.current];
}

inline fn isAtEnd(self: *Parser) bool {
    return self.file.current >= self.file.tokens.items.len;
}

fn checkEof(self: *Parser) !void {
    if (self.isAtEnd()) {
        return self.reportError("Unexpected end of file\n", .{});
    }
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

inline fn expect(self: *Parser, comptime kind: Token.Kind) !Token {
    return self.expectOneOf(.{kind});
}

fn synchronize(self: *Parser) void {
    while (!self.isAtEnd() and !(self.peek().kind == .SemiColon or self.peek().kind == .CurlyRight)) {
        _ = self.advance();
    }
    if (!self.isAtEnd() and (self.peek().kind == .SemiColon or self.peek().kind == .CurlyRight)) {
        _ = self.advance();
    }
}

inline fn makeLeaf(kind: Node.Kind, token_index: ?u32) Node {
    return Node{ .kind = kind, .children = 0, .token_index = token_index };
}

inline fn pushNode(self: *Parser, node: Node) !void {
    try self.file.ast.append(self.allocator, node);
}

inline fn lastPushed(self: *Parser) *Node {
    var node = self.file.ast.getLast();
    return &node;
}

fn reportError(self: *Parser, comptime fmt: []const u8, args: anytype) error{ UnexpectedEof, UnexpectedToken } {
    self.file.success = false;
    const len: u32 = @intCast(self.file.buffer.len);
    const token = if (self.isAtEnd()) Token{ .kind = .Invalid, .start = len, .end = len } else self.peek();
    const err = if (self.isAtEnd()) error.UnexpectedEof else error.UnexpectedToken;

    const line_info = self.file.lineInfo(token);
    const column_number = token.start - line_info.start;
    const line = File.getLine(self.file.buffer, line_info.start, token.start, len);

    self.printer.printSourceLine(fmt, args, self.file, line_info.number, column_number, line, token.len());
    return err;
}

fn parseDeclaration(self: *Parser) !void {
    const declaration_index = self.file.current;
    const declaration = try self.expectOneOf(.{ .Var, .Const });
    try self.pushNode(.{ .kind = .Declaration, .children = 3, .token_index = declaration_index });

    const name_identifier_index = self.file.current;
    _ = try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, name_identifier_index));

    const token = switch (declaration.kind) {
        .Const => try self.expectOneOf(.{ .Colon, .Equals }),
        .Var => try self.expectOneOf(.{ .Colon, .ColonEquals }),
        else => unreachable,
    };
    var type_identifier_index: ?u32 = null;
    if (token.kind == .Colon) {
        type_identifier_index = self.file.current;
        _ = try self.expect(.Identifier);
        _ = try self.expect(.Equals);
    }
    try self.pushNode(makeLeaf(.TypeIdentifier, type_identifier_index));

    const expression = try self.parseExpression();
    try self.pushNode(expression);
    _ = try self.expect(.SemiColon);
}

fn parseBlock(self: *Parser) Error!void {
    _ = try self.expect(.CurlyLeft);
    try self.pushNode(.{ .kind = .Scope, .children = 0 });
    var scope_node = self.lastPushed();

    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .CurlyRight) {
        self.parseNode() catch {
            self.synchronize();
            continue;
        };
        children += 1;
    }
    _ = try self.expect(.CurlyRight);

    scope_node.children = children;
}

fn parseFunction(self: *Parser) !void {
    _ = try self.expect(.Fn);
    try self.pushNode(.{ .kind = .Function, .children = 4 });

    const identifier_index = self.file.current;
    _ = try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, identifier_index));

    _ = try self.expect(.ParenLeft);
    try self.pushNode(.{ .kind = .Parameters, .children = 0 });
    var parameters = self.lastPushed();
    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .ParenRight) {
        const identifier_index = self.file.current;
        _ = try self.expect(.Identifier);
        _ = try self.expect(.Colon);
        const type_index = self.file.current;
        _ = try self.expect(.Identifier);
        const children = try self.nodesFromTuple(.{
            makeLeaf(.Identifier, identifier_index),
            makeLeaf(.Identifier, type_index),
        });
        const parameter = Node{ .kind = .Parameter, .children = children };
        try parameters.append(self.allocator, parameter);
        if (self.peek().kind == .Comma) {
            _ = self.advance();
        }
    }
    parameters.children = children;
    _ = try self.expect(.ParenRight);

    const type_index = self.file.current;
    _ = try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, type_index));

    const block = try self.parseBlock();
    try self.pushNode(block);
}

fn parseReturn(self: *Parser) !void {
    const return_index = self.file.current;
    _ = try .expect(.Return);
    try self.pushNode(.{ .kind = .Keyword, .children = 1, .token_index = return_index });

    const expression = try self.parseExpression();
    try self.pushNode(expression);
    _ = try self.expect(.SemiColon);
}

fn parseIdentifier(self: *Parser) !void {
    const expression = try self.parseExpression();
    try self.pushNode(expression);
    _ = try self.expect(.SemiColon);
}

fn parseArguments(self: *Parser) !Node {
    var arguments: std.ArrayList(Node) = .empty;
    while (!self.isAtEnd() and self.peek().kind != .ParenRight) {
        const identifier_index = self.file.current;
        const token = try self.expectOneOf(.{ .Identifier, .IntLiteral, .FloatLiteral });
        if (self.peek().kind == .Comma) {
            _ = self.advance();
        }
        const argument_kind: Node.Kind = switch (token.kind) {
            .Identifier => .Identifier,
            .IntLiteral => .IntLiteral,
            .FloatLiteral => .FloatLiteral,
            else => unreachable,
        };
        const argument: Node = .{ .kind = argument_kind, .children = &.{}, .token_index = identifier_index };
        try arguments.append(self.allocator, argument);
        if (self.peek().kind == .Comma) {
            _ = self.advance();
        }
    }
    const children = try arguments.toOwnedSlice(self.allocator);
    return .{ .kind = .Parameters, .children = children };
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
        .IntLiteral => return makeLeaf(.IntLiteral, self.advance()),
        .FloatLiteral => return makeLeaf(.FloatLiteral, self.advance()),
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
            return .{ .kind = .UnaryMinus, .children = children, .token_index = token_index };
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
            const kind: Node.Kind = switch (token.kind) {
                .Plus => .BinaryPlus,
                .Minus => .BinaryMinus,
                .Star => .BinaryStar,
                .Slash => .BinarySlash,
                else => unreachable,
            };
            return Node{ .kind = kind, .children = children, .token_index = token_index };
        },
        .ParenLeft => {
            const arguments = try self.parseArguments();
            _ = try self.expect(.ParenRight);
            const children = try self.nodesFromTuple(.{ left, arguments });
            return Node{ .kind = .Call, .children = children, .token_index = token_index };
        },
        else => return self.reportError("Unexpected infixOrSuffix: {any}\n", .{token.kind}),
    }
}
