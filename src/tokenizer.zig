const std = @import("std");

const Printer = @import("printer.zig");
const Token = @import("token.zig");
const File = @import("file.zig");

const Tokenizer = @This();
allocator: std.mem.Allocator,
printer: Printer,
file: *File,

pub const Error = error{} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, printer: Printer, file: *File) Tokenizer {
    return .{
        .allocator = allocator,
        .printer = printer,
        .file = file,
    };
}

pub fn tokenize(self: *Tokenizer) Error!void {
    try self.file.ensureTokensCapacity();
    while (!self.isAtEnd()) {
        const token = self.nextToken();
        switch (token.kind) {
            .Newline, .Comment, .EscapeSequence => continue,
            else => {},
        }
        try self.file.tokens.append(self.allocator, token);
    }
    self.file.printTokens();
}

pub fn nextToken(self: *Tokenizer) Token {
    return switch (self.peek()) {
        ' ', '\t', '\r' => self.escapeSequenceToken(),
        '_', 'a'...'z', 'A'...'Z' => self.identifierToken(),
        '0'...'9' => self.numberLiteralToken(),
        '\n' => self.newLineToken(),
        ';' => self.oneCharToken(.SemiColon),
        ',' => self.oneCharToken(.Comma),
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
        else => self.unsupportedByte(),
    };
}

inline fn advance(self: *Tokenizer) void {
    self.file.position += 1;
}

inline fn advanceGetIndex(self: *Tokenizer) u32 {
    self.file.position += 1;
    return self.file.position - 1;
}

inline fn peek(self: *Tokenizer) u8 {
    return self.file.buffer[self.file.position];
}

inline fn isAtEnd(self: *Tokenizer) bool {
    return self.file.position >= self.file.buffer.len;
}

inline fn isIdentifierChar(self: *Tokenizer) bool {
    return switch (self.peek()) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn oneCharToken(self: *Tokenizer, kind: Token.Kind) Token {
    const start = self.advanceGetIndex();
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn twoCharToken(self: *Tokenizer, kind_one: Token.Kind, char_two: u8, kind_two: Token.Kind) Token {
    const start = self.advanceGetIndex();
    if (!self.isAtEnd() and self.peek() == char_two) {
        self.advance();
        return .{ .kind = kind_two, .start = start, .end = self.file.position };
    }
    return .{ .kind = kind_one, .start = start, .end = self.file.position };
}

fn newLineToken(self: *Tokenizer) Token {
    self.file.line_number += 1;
    self.file.line_start = self.file.position + 1;
    return self.oneCharToken(.Newline);
}

fn escapeSequenceToken(self: *Tokenizer) Token {
    const start = self.advanceGetIndex();
    return .{ .kind = .EscapeSequence, .start = start, .end = self.file.position };
}

fn slashToken(self: *Tokenizer) Token {
    const start = self.advanceGetIndex();
    var kind: Token.Kind = .Slash;
    if (!self.isAtEnd() and self.peek() == '/') {
        self.advance();
        while (!self.isAtEnd() and self.peek() != '\n') {
            self.advance();
        }
        kind = .Comment;
    }
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn numberLiteralToken(self: *Tokenizer) Token {
    const start = self.file.position;
    var has_dot = false;
    var is_float = false;
    while (!self.isAtEnd()) {
        switch (self.peek()) {
            '0'...'9', '_' => {
                self.advance();
                if (has_dot) {
                    is_float = true;
                }
            },
            '.' => {
                if (!has_dot) {
                    self.advance();
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
    const kind: Token.Kind = if (is_float) .FloatLiteral else .IntLiteral;
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn identifierToken(self: *Tokenizer) Token {
    const start = self.file.position;
    while (!self.isAtEnd() and self.isIdentifierChar()) {
        self.advance();
    }
    const word = self.file.buffer[start..self.file.position];
    const kind = Token.keywords.get(word) orelse .Identifier;
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn unsupportedByte(self: *Tokenizer) Token {
    const start = self.file.position;
    self.advance();
    return .{ .kind = .InvalidByte, .start = start, .end = self.file.position };
}
