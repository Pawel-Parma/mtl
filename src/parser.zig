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
        .Identifier, .At => try self.parseExpressionStatement(),
        .Underscore => try self.parseUnderscore(),
        else => self.reportError("Unexpected token {any}\n", .{token}),
    };
}

inline fn advance(self: *Parser) void {
    self.file.current += 1;
}

inline fn index(self: *Parser) u32 {
    return self.file.current;
}

inline fn advanceGetIndex(self: *Parser) u32 {
    self.file.current += 1;
    return self.file.current - 1;
}

inline fn peek(self: *Parser) Token {
    return self.file.tokens.items[self.file.current];
}

inline fn peekNext(self: *Parser) Token {
    return self.file.tokens.items[self.file.current + 1];
}

inline fn isIndexAtEnd(self: *Parser, idx: u32) bool {
    return idx >= self.file.tokens.items.len;
}

inline fn isAtEnd(self: *Parser) bool {
    return self.isIndexAtEnd(self.file.current);
}

inline fn checkEofAtIndex(self: *Parser, idx: u32) !void {
    if (self.isIndexAtEnd(idx)) {
        return self.reportError("Unexpected end of file\n", .{});
    }
}

inline fn checkEof(self: *Parser) !void {
    try self.checkEofAtIndex(self.file.current);
}

inline fn checkEofNext(self: *Parser) !void {
    try self.checkEofAtIndex(self.file.current + 1);
}

fn expectOneOf(self: *Parser, comptime kinds: anytype) !Token {
    try self.checkEof();
    const token = self.peek();
    inline for (kinds) |kind| {
        if (token.kind == kind) {
            self.advance();
            return token;
        }
    }
    return self.reportError("Expected token kind to be one of {any}, found {any}\n", .{ kinds, token.kind });
}

inline fn expect(self: *Parser, comptime kind: Token.Kind) !void {
    _ = try self.expectOneOf(.{kind});
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

inline fn pushNodes(self: *Parser, nodes: []const Node) !void {
    try self.file.ast.appendSlice(self.allocator, nodes);
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
    const token = if (self.isAtEnd()) Token{ .kind = .Eof, .start = len - 1, .end = len } else self.peek();
    self.printer.printSourceLine(fmt, args, self.file, token);
    return Error.ParsingFailed;
}

fn parseDeclaration(self: *Parser) !void {
    const declaration_index = self.index();
    const declaration = try self.expectOneOf(.{ .Var, .Const });
    try self.pushNode(.{ .kind = .Declaration, .children = 3, .token_index = declaration_index });

    const name_identifier_index = self.index();
    try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, name_identifier_index));

    // const a = 1;
    // const a: u32 = 1;
    const token = switch (declaration.kind) {
        .Const => try self.expectOneOf(.{ .Colon, .Equals }),
        .Var => try self.expectOneOf(.{ .Colon, .ColonEquals }),
        else => unreachable,
    };
    if (token.kind == .Colon) {
        try self.pushNode(.{ .kind = .TypeExpression, .children = 1 });
        const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
        try self.pushNodes(expression);
        try self.expect(.Equals);
    } else {
        try self.pushNode(makeLeaf(.TypeExpression, null));
    }

    try self.parseExpression();
    try self.expect(.SemiColon);
}

fn parseFunction(self: *Parser) !void {
    const fn_index = self.index();
    try self.expect(.Fn);
    try self.pushNode(.{ .kind = .Function, .children = 4, .token_index = fn_index });

    const identifier_index = self.index();
    try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, identifier_index));

    try self.expect(.ParenLeft);
    try self.parseParameters();
    try self.expect(.ParenRight);

    const type_index = self.index();
    try self.expect(.Identifier);
    try self.pushNode(makeLeaf(.Identifier, type_index));

    try self.parseBlock();
}

fn parseParameters(self: *Parser) !void {
    try self.pushNode(.{ .kind = .Parameters, .children = 0 });
    const parameters_index = self.lastPushedIndex();

    var children: u32 = 0;
    while (!self.isAtEnd() and self.peek().kind != .ParenRight) : (children += 1) {
        try self.pushNode(.{ .kind = .Parameter, .children = 2 });

        const parameter_identifier_index = self.index();
        try self.expect(.Identifier);
        try self.pushNode(makeLeaf(.Identifier, parameter_identifier_index));
        try self.expect(.Colon);

        const type_index = self.index();
        try self.expect(.Identifier);
        try self.pushNode(makeLeaf(.Identifier, type_index));

        if (self.peek().kind == .Comma) {
            self.advance();
        }
    }

    self.file.ast.items[parameters_index].children = children;
}

fn parseBlock(self: *Parser) Error!void {
    try self.expect(.CurlyLeft);
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
    try self.expect(.CurlyRight);

    self.file.ast.items[scope_index].children = children;
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

fn parseReturn(self: *Parser) !void {
    const return_index = self.index();
    try self.expect(.Return);
    if (!self.isAtEnd() and self.peek().kind != .SemiColon) {
        try self.pushNode(.{ .kind = .Return, .children = 1, .token_index = return_index });
        try self.parseExpression();
    } else {
        try self.pushNode(.{ .kind = .Return, .children = 0, .token_index = return_index });
    }
    try self.expect(.SemiColon);
}

fn parseExpressionStatement(self: *Parser) !void {
    const id = try self.expectOneOf(.{ .Identifier, .At });
    if (id.kind == .Identifier) {
        try self.pushNode(.{ .kind = .ExpressionStatement, .children = 1 });
        self.file.current -= 1;
        try self.checkEofNext();
        const token_next = self.peekNext();
        switch (token_next.kind) {
            .ParenLeft => {
                const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
                try self.file.ast.appendSlice(self.allocator, expression);
            },
            .Equals, .PlusEquals, .MinusEquals, .StarEquals, .SlashEquals, .PercentEquals, .CaretEquals => {
                try self.pushNode(.{ .kind = .Mutation, .children = 3 });
                try self.pushNode(.{ .kind = .Identifier, .children = 0, .token_index = self.file.current });
                self.advance();
                const kind: Node.Kind = switch (token_next.kind) {
                    .Equals => .Equals,
                    .PlusEquals => .PlusEquals,
                    .MinusEquals => .MinusEquals,
                    .StarEquals => .StarEquals,
                    .SlashEquals => .SlashEquals,
                    .PercentEquals => .PercentEquals,
                    .CaretEquals => .CaretEquals,
                    else => unreachable,
                };
                try self.pushNode(.{ .kind = kind, .children = 0 });
                self.advance();
                try self.parseExpression();
            },
            else => {
                self.advance();
                return self.reportError("Unexpected token {any} in parseExpressionStatement\n", .{token_next.kind});
            },
        }
    } else {
        self.file.current -= 1;
        const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
        try self.file.ast.appendSlice(self.allocator, expression);
    }

    try self.expect(.SemiColon);
}

fn parseUnderscore(self: *Parser) !void {
    try self.expect(.Underscore);
    try self.pushNode(.{ .kind = .IgnoreResult, .children = 1 });
    try self.expect(.Equals);
    try self.parseExpression();
    try self.expect(.SemiColon);
}

inline fn parseExpression(self: *Parser) !void {
    try self.pushNode(.{ .kind = .Expression, .children = 1 });
    const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
    try self.pushNodes(expression);
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
        .Identifier, .IntDecimalLiteral, .IntBinaryLiteral, .IntOctalLiteral, .IntHexadecimalLiteral, .IntScientificLiteral, .FloatLiteral, .FloatScientificLiteral, .TrueLiteral, .FalseLiteral => {
            const kind: Node.Kind = switch (token.kind) {
                .Identifier => .Identifier,
                .IntDecimalLiteral => .IntLiteral,
                .IntBinaryLiteral => .IntBinaryLiteral,
                .IntOctalLiteral => .IntOctalLiteral,
                .IntHexadecimalLiteral => .IntHexadecimalLiteral,
                .IntScientificLiteral => .IntScientificLiteral,
                .FloatLiteral => .FloatLiteral,
                .FloatScientificLiteral => .FloatScientificLiteral,
                .TrueLiteral => .TrueLiteral,
                .FalseLiteral => .FalseLiteral,
                else => unreachable,
            };
            return self.nodesToHeapSlice(.{makeLeaf(kind, token_index)});
        },
        .Minus, .Not => {
            const kind: Node.Kind = switch (token.kind) {
                .Minus => .UnaryMinus,
                .Not => .UnaryNot,
                else => unreachable,
            };
            const node = Node{ .kind = kind, .children = 1, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Prefix);
            return self.nodesToHeapSlice(.{ node, expression });
        },
        .ParenLeft => {
            const grouping = Node{ .kind = .Grouping, .children = 1, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(Token.Precedence.Lowest);
            try self.expect(.ParenRight);
            return self.nodesToHeapSlice(.{ grouping, expression });
        },
        .At => {
            const builtin_node = Node{ .kind = .Builtin, .children = 2 };

            const identifier_index = self.index();
            try self.expect(.Identifier);
            const identifier_node = makeLeaf(.Identifier, identifier_index);

            try self.expect(.ParenLeft);
            const arguments = try self.parseArguments();
            try self.expect(.ParenRight);

            return self.nodesToHeapSlice(.{ builtin_node, identifier_node, arguments });
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
        .Plus, .Minus, .Star, .Slash, .Percent, .DoubleEquals, .BangEquals, .GraterThan, .GraterEqualsThan, .LesserThan, .LesserEqualsThan, .And, .Or, .Caret => {
            const kind: Node.Kind = switch (token.kind) {
                .Plus => .BinaryPlus,
                .Minus => .BinaryMinus,
                .Star => .BinaryStar,
                .Slash => .BinarySlash,
                .Percent => .BinaryPercent,
                .DoubleEquals => .BinaryDoubleEquals,
                .BangEquals => .BinaryBangEquals,
                .GraterThan => .BinaryGraterThan,
                .GraterEqualsThan => .BinaryGraterEqualsThan,
                .LesserThan => .BinaryLesserThan,
                .LesserEqualsThan => .BinaryLesserEqualsThan,
                .And => .BinaryAnd,
                .Or => .BinaryOr,
                .Caret => .BinaryCaret,
                else => unreachable,
            };
            const operator = Node{ .kind = kind, .children = 2, .token_index = token_index };
            const expression = try self.parseExpressionWithPrecedence(token.precedence());
            return self.nodesToHeapSlice(.{ operator, left, expression });
        },
        .ParenLeft => {
            const call = Node{ .kind = .Call, .children = 2, .token_index = token_index };
            const arguments = try self.parseArguments();
            try self.expect(.ParenRight);
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
