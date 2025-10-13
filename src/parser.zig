const std = @import("std");

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
        .Identifier => try self.parseExpressionStatement(),
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
    return &self.file.ast.items[self.file.ast.items.len - 1];
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

    try self.parseExpression();
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
    try self.parseParameters();
    _ = try self.expect(.ParenRight);

    const type_index = self.file.current;
    _ = try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, type_index));

    try self.parseBlock();
}

fn parseParameters(self: *Parser) !void {
    try self.pushNode(.{ .kind = .Parameters, .children = 0 });
    var parameters = self.lastPushed();

    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .ParenRight) : (children += 1) {
        try self.pushNode(.{ .kind = .Parameter, .children = 2 });

        const parameter_identifier_index = self.file.current;
        _ = try self.expect(.Identifier);
        try self.pushNode(makeLeaf(.Identifier, parameter_identifier_index));
        _ = try self.expect(.Colon);

        const type_index = self.file.current;
        _ = try self.expect(.Identifier);
        try self.pushNode(makeLeaf(.Identifier, type_index));
        if (self.peek().kind == .Comma) {
            _ = self.advance();
        }
    }
    parameters.children = children;
}

fn parseReturn(self: *Parser) !void {
    const return_index = self.file.current;
    _ = try self.expect(.Return);
    try self.pushNode(.{ .kind = .Return, .children = 1, .token_index = return_index });

    try self.parseExpression();
    _ = try self.expect(.SemiColon);
}

fn parseExpressionStatement(self: *Parser) !void { // TODO:
    try self.parseExpression();
    _ = try self.expect(.SemiColon);
}

inline fn parseExpression(self: *Parser) !void {
    const expressions = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
    for (expressions) |expression| {
        try self.pushNode(expression);
    }
}

fn parseExpressionWithPrecedence(self: *Parser, precedence: Token.Precedence) Error![]Node {
    var left = try self.parsePrefix();
    while (!self.isAtEnd()) {
        const next = self.peek();
        if (next.precedence().lessThan(precedence) or (next.precedence() == precedence and next.associativity() == .Left)) {
            break;
        }
        left = try self.parseInfixOrSuffix(left);
    }
    return left;
}

fn parsePrefix(self: *Parser) Error![]Node {
    try self.checkEof();
    const token = self.peek();
    const token_index = self.advance();
    switch (token.kind) {
        .Identifier => return try self.nodesToHeapSlice(&.{makeLeaf(.Identifier, token_index)}),
        .IntLiteral => return try self.nodesToHeapSlice(&.{makeLeaf(.IntLiteral, token_index)}),
        .FloatLiteral => return try self.nodesToHeapSlice(&.{makeLeaf(.FloatLiteral, token_index)}),
        .Minus => {
            const minus = Node{ .kind = .UnaryMinus, .children = 1, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Prefix);
            return try self.nodesToHeapSlice(try std.mem.concat(self.allocator, Node, &.{ &.{minus}, expression }));
        },
        .ParenLeft => {
            const grouping = Node{ .kind = .Expression, .children = 1, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
            _ = try self.expect(.ParenRight);
            return try self.nodesToHeapSlice(try std.mem.concat(self.allocator, Node, &.{ &.{grouping}, expression }));
        },
        else => return self.reportError("Unexpected prefix: {any}\n", .{token.kind}),
    }
}

fn parseInfixOrSuffix(self: *Parser, left: []Node) ![]Node {
    const token = self.peek();
    const token_index = self.advance();
    switch (token.kind) {
        .Plus, .Minus, .Star, .Slash => {
            const kind: Node.Kind = switch (token.kind) {
                .Plus => .BinaryPlus,
                .Minus => .BinaryMinus,
                .Star => .BinaryStar,
                .Slash => .BinarySlash,
                else => unreachable,
            };
            const operator = Node{ .kind = kind, .children = 2, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(token.precedence());
            return try self.nodesToHeapSlice(try std.mem.concat(self.allocator, Node, &.{ &.{operator}, left, expression }));
        },
        .ParenLeft => {
            const call = Node{ .kind = .Call, .children = 2, .token_index = token_index };
            const arguments = try self.parseArguments();
            _ = try self.expect(.ParenRight);
            return try self.nodesToHeapSlice(try std.mem.concat(self.allocator, Node, &.{ &.{call}, left, arguments }));
        },
        else => return self.reportError("Unexpected infixOrSuffix: {any}\n", .{token.kind}),
    }
}

fn parseArguments(self: *Parser) ![]Node {
    try self.pushNode(.{ .kind = .Parameters, .children = 0 });
    var arguments = self.lastPushed();
    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .ParenRight) {
        const identifier_index = self.file.current;
        const token = try self.expectOneOf(.{ .Identifier, .IntLiteral, .FloatLiteral }); // TODO: allow to pass expressions as arguments
        const kind: Node.Kind = switch (token.kind) {
            .Identifier => .Identifier,
            .IntLiteral => .IntLiteral,
            .FloatLiteral => .FloatLiteral,
            else => unreachable,
        };
        try self.pushNode(.{ .kind = kind, .children = 0, .token_index = identifier_index });
        children += 1;
        if (self.peek().kind == .Comma) {
            _ = self.advance();
        }
    }
    arguments.children = children;
    var nod: [1]Node = .{Node{ .kind = .Return, .children = 0 }};
    return &nod;
}

inline fn nodesToHeapSlice(self: *Parser, nodes: []const Node) ![]Node {
    var slice = try self.allocator.alloc(Node, nodes.len);
    for (nodes, 0..) |node, i| {
        slice[i] = node;
    }
    return slice;
}
