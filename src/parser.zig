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
        .Var, .Const => try self.parseDeclaration(),
        .Fn => try self.parseFunction(),
        .Pub => try self.parsePub(),
        .CurlyLeft => try self.parseBlock(),
        .Return => try self.parseReturn(),
        .Identifier => try self.parseExpressionStatement(),
        else => self.reportError("Unexpected token {any}\n", .{token}),
    };
}

inline fn advance(self: *Parser) void {
    self.file.current += 1;
}

inline fn advanceGetIndex(self: *Parser) u32 {
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
    self.advance();
    return token;
}

inline fn expect(self: *Parser, comptime kind: Token.Kind) !Token {
    return self.expectOneOf(.{kind});
}

fn synchronize(self: *Parser) void {
    while (!self.isAtEnd() and !(self.peek().kind == .SemiColon or self.peek().kind == .CurlyRight)) {
        self.advance();
    }
    if (!self.isAtEnd() and (self.peek().kind == .SemiColon or self.peek().kind == .CurlyRight)) {
        self.advance();
    }
}

inline fn makeLeaf(kind: Node.Kind, token_index: ?u32) Node {
    return Node{ .kind = kind, .children = 0, .token_index = token_index };
}

inline fn pushNode(self: *Parser, node: Node) !void {
    try self.file.ast.append(self.allocator, node);
}

inline fn lastPushedIndex(self: *Parser) u32 {
    return @intCast(self.file.ast.items.len - 1);
}

fn nodesToHeapSlice(self: *Parser, nodes: anytype) ![]Node {
    var slice: std.ArrayList(Node) = .empty;
    inline for (nodes) |node| {
        switch (@TypeOf(node)) {
            Node => try slice.append(self.allocator, node),
            []Node => try slice.appendSlice(self.allocator, node),
            else => @compileError("unexpected type"),
        }
    }
    return slice.items;
}

fn reportError(self: *Parser, comptime fmt: []const u8, args: anytype) Error {
    self.file.success = false;
    const len: u32 = @intCast(self.file.buffer.len);
    const token = if (self.isAtEnd()) Token{ .kind = .Eof, .start = len, .end = len } else self.peek();
    self.printer.printSourceLine(fmt, args, self.file, token);
    return Error.ParsingFailed;
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

fn parseFunction(self: *Parser) !void {
    const fn_index = self.file.current;
    _ = try self.expect(.Fn);
    try self.pushNode(.{ .kind = .Function, .children = 4, .token_index = fn_index });

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
    const parameters_index = self.lastPushedIndex();

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
            self.advance();
        }
    }
    self.file.ast.items[parameters_index].children = children;
}

fn parsePub(self: *Parser) !void {
    const token_index = self.advanceGetIndex();
    try self.pushNode(.{ .kind = .Public, .children = 1, .token_index = token_index });
    const token = self.peek();
    return switch (token.kind) {
        .Var, .Const => self.parseDeclaration(),
        .Fn => self.parseFunction(),
        else => self.reportError("unexpected token {any} after pub\n", .{token}),
    };
}

fn parseBlock(self: *Parser) Error!void {
    _ = try self.expect(.CurlyLeft);
    try self.pushNode(.{ .kind = .Scope, .children = 0 });
    const scope_index = self.lastPushedIndex();

    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .CurlyRight) {
        self.parseNode() catch {
            self.synchronize();
            continue;
        };
        children += 1;
    }
    _ = try self.expect(.CurlyRight);

    self.file.ast.items[scope_index].children = children;
}

fn parseReturn(self: *Parser) !void {
    const return_index = self.file.current;
    _ = try self.expect(.Return);
    try self.pushNode(.{ .kind = .Return, .children = 0, .token_index = return_index });

    if (!self.isAtEnd() and self.peek().kind != .SemiColon) {
        self.file.ast.items[self.lastPushedIndex()].children = 1;
        try self.parseExpression();
    }
    _ = try self.expect(.SemiColon);
}

fn parseExpressionStatement(self: *Parser) !void {
    try self.pushNode(.{ .kind = .ExpressionStatement, .children = 1 });
    const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
    try self.file.ast.appendSlice(self.allocator, expression);
    _ = try self.expect(.SemiColon);
}

inline fn parseExpression(self: *Parser) !void {
    try self.pushNode(.{ .kind = .Expression, .children = 1 });
    const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
    try self.file.ast.appendSlice(self.allocator, expression);
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
    const token_index = self.advanceGetIndex();
    switch (token.kind) {
        .Identifier => return self.nodesToHeapSlice(.{makeLeaf(.Identifier, token_index)}),
        .IntLiteral => return self.nodesToHeapSlice(.{makeLeaf(.IntLiteral, token_index)}),
        .FloatLiteral => return self.nodesToHeapSlice(.{makeLeaf(.FloatLiteral, token_index)}),
        .Minus => {
            const minus = Node{ .kind = .UnaryMinus, .children = 1, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Prefix);
            return self.nodesToHeapSlice(.{ minus, expression });
        },
        .ParenLeft => {
            const grouping = Node{ .kind = .Grouping, .children = 1, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
            _ = try self.expect(.ParenRight);
            return self.nodesToHeapSlice(.{ grouping, expression });
        },
        else => {
            self.file.current -= 1;
            return self.reportError("Unexpected prefix: {any}\n", .{token.kind});
        },
    }
}

fn parseInfixOrSuffix(self: *Parser, left: []Node) ![]Node {
    const token = self.peek();
    const token_index = self.advanceGetIndex();
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
            return self.nodesToHeapSlice(.{ operator, left, expression });
        },
        .ParenLeft => {
            const call = Node{ .kind = .Call, .children = 2, .token_index = token_index };
            const arguments = try self.parseArguments();
            _ = try self.expect(.ParenRight);
            return self.nodesToHeapSlice(.{ call, left, arguments });
        },
        else => {
            self.file.current -= 1;
            return self.reportError("Unexpected infix or suffix: {any}\n", .{token.kind});
        },
    }
}

fn parseArguments(self: *Parser) ![]Node {
    var arguments: std.ArrayList(Node) = .empty;
    try arguments.append(self.allocator, .{ .kind = .Arguments, .children = 0 });
    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .ParenRight) : (children += 1) {
        try arguments.append(self.allocator, .{ .kind = .Argument, .children = 1 });
        try arguments.append(self.allocator, .{ .kind = .Expression, .children = 1 });
        const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
        try arguments.appendSlice(self.allocator, expression);
        if (self.peek().kind == .Comma) {
            self.advance();
        }
    }
    arguments.items[0].children = children;
    return arguments.items;
}
