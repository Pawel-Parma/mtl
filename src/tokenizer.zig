const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");

const Tokenizer = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
file_path: []const u8,
position: usize,
line_number: usize,
line_start: usize,
success_state: Error!void,
tokens: std.ArrayList(Token),

pub const Error = error{
    TokenizeFailed,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8, file_path: []const u8) Tokenizer {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .file_path = file_path,
        .position = 0,
        .line_number = 1,
        .line_start = 0,
        .success_state = void{},
        .tokens = .empty,
    };
}

pub fn deinit(self: *Tokenizer) void {
    self.tokens.deinit(self.allocator);
}

pub fn tokenize(self: *Tokenizer) Error!void {
    const initialCapacity = @min(512, self.buffer.len / 2);
    try self.tokens.ensureTotalCapacityPrecise(self.allocator, initialCapacity);
    while (!self.isAtEnd()) {
        const token = self.nextToken() orelse continue;
        try self.tokens.append(self.allocator, token);
    }
    self.printTokens();
    return self.success_state;
}

pub fn nextToken(self: *Tokenizer) ?Token {
    return switch (self.peek()) {
        ' ', '\t', '\r', '\x0B', '\x0C' => blk: {
            _ = self.advance();
            break :blk null;
        },
        '\n' => blk: {
            self.advanceLine();
            break :blk null;
        },
        'a'...'z', 'A'...'Z' => self.identifierToken(),
        '0'...'9' => self.numberLiteralToken(),
        ';' => self.oneCharToken(.Semicolon),
        '-' => self.oneCharToken(.Minus),
        '+' => self.oneCharToken(.Plus),
        '*' => self.oneCharToken(.Star),
        '/' => self.slashToken(),
        '(' => self.oneCharToken(.ParenLeft),
        ')' => self.oneCharToken(.ParenRight),
        '{' => self.oneCharToken(.CurlyLeft),
        '}' => self.oneCharToken(.CurlyRight),
        ':' => self.twoCharToken(.Colon, '=', .ColonEquals),
        '=' => self.twoCharToken(.Equals, '=', .DoubleEquals),
        else => self.unsupportedCharacter(),
    };
}

inline fn advance(self: *Tokenizer) usize {
    self.position += 1;
    return self.position - 1;
}

inline fn advanceLine(self: *Tokenizer) void {
    self.position += 1;
    self.line_number += 1;
    self.line_start = self.position;
}

inline fn peek(self: *Tokenizer) u8 {
    return self.buffer[self.position];
}

inline fn isAtEnd(self: *Tokenizer) bool {
    return self.position >= self.buffer.len;
}

inline fn isIdentifierChar(self: *Tokenizer) bool {
    const c = self.peek();
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn oneCharToken(self: *Tokenizer, kind: Token.Kind) Token {
    const start = self.advance();
    return .{ .kind = kind, .start = start, .end = self.position };
}

fn twoCharToken(self: *Tokenizer, kind_one: Token.Kind, char_two: u8, kind_two: Token.Kind) Token {
    const start = self.advance();
    if (!self.isAtEnd() and self.peek() == char_two) {
        _ = self.advance();
        return .{ .kind = kind_two, .start = start, .end = self.position };
    }
    return .{ .kind = kind_one, .start = start, .end = self.position };
}

fn slashToken(self: *Tokenizer) ?Token {
    const start = self.advance();
    if (!self.isAtEnd() and self.peek() == '/') {
        _ = self.advance();
        while (!self.isAtEnd() and self.peek() != '\n') {
            _ = self.advance();
        }
        return null;
    }
    return .{ .kind = .Slash, .start = start, .end = self.position };
}

fn numberLiteralToken(self: *Tokenizer) Token {
    const start = self.position;
    var has_dot = false;
    while (!self.isAtEnd()) {
        switch (self.peek()) {
            '0'...'9', '_' => _ = self.advance(),
            '.' => {
                if (!has_dot) {
                    _ = self.advance();
                    switch (self.peek()) {
                        '0'...'9', '_' => {},
                        else => break,
                    }
                    has_dot = true;
                }
            },
            else => break,
        }
    }
    const kind: Token.Kind = if (has_dot) .FloatLiteral else .IntLiteral;
    return .{ .kind = kind, .start = start, .end = self.position };
}

fn identifierToken(self: *Tokenizer) Token {
    const start = self.position;
    while (!self.isAtEnd() and self.isIdentifierChar()) {
        _ = self.advance();
    }
    const word = self.buffer[start..self.position];
    const kind = Token.KeywordMap.get(word) orelse .Identifier;
    return .{ .kind = kind, .start = start, .end = self.position };
}

fn unsupportedCharacter(self: *Tokenizer) Token {
    self.success_state = Error.TokenizeFailed;

    const len = std.unicode.utf8ByteSequenceLength(self.peek()) catch unreachable;
    self.position += len;

    const column_number = self.position - self.line_start - len;
    const line_end = std.mem.indexOfScalarPos(u8, self.buffer, self.position, '\n') orelse self.buffer.len - self.position;
    const line = self.buffer[self.line_start..line_end];

    core.printSourceLine("encountered unsupported character", self.file_path, self.line_number, column_number, line);
    return .{ .kind = .Invalid, .start = self.position - len, .end = self.position };
}

fn printTokens(self: *Tokenizer) void {
    core.dprint("\nTokens:\n", .{});
    for (self.tokens.items) |token| {
        core.dprint("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, token.string(self.buffer) });
    }
    core.dprint("\n", .{});
}
