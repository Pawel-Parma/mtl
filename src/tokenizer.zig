const std = @import("std");

const Token = @import("token.zig");
const File = @import("file.zig");

const Tokenizer = @This();
allocator: std.mem.Allocator,
file: *File,

pub const Error = error{} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, file: *File) Tokenizer {
    return .{
        .allocator = allocator,
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
        '@', '^', ';', ',', '(', ')', '{', '}' => self.charToken(),
        '+', '-', '*', '%', ':', '=', '!', '>', '<' => self.charEqualsToken(),
        ' ', '\t', '\r' => self.escapeSequenceToken(),
        'a'...'z', 'A'...'Z' => self.identifierToken(),
        '_' => self.underscoreToken(),
        '\n' => self.newLineToken(),
        '/' => self.slashToken(),
        '0'...'9' => self.numberLiteralToken(),
        else => self.invalidByte(),
    };
}

inline fn index(self: *Tokenizer) u32 {
    return self.file.position;
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

inline fn peekNext(self: *Tokenizer) u8 {
    return self.file.buffer[self.file.position + 1];
}

inline fn isAtEnd(self: *Tokenizer) bool {
    return self.file.position >= self.file.buffer.len;
}

inline fn isNextAtEnd(self: *Tokenizer) bool {
    return self.file.position + 1 >= self.file.buffer.len;
}

inline fn isIdentifierChar(char: u8) bool {
    return switch (char) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

inline fn isBinaryDigitChar(char: u8) bool {
    return switch (char) {
        '0'...'1' => true,
        else => false,
    };
}

inline fn isOctalDigitChar(char: u8) bool {
    return switch (char) {
        '0'...'7' => true,
        else => false,
    };
}

inline fn isDecimalDigitChar(char: u8) bool {
    return switch (char) {
        '0'...'9' => true,
        else => false,
    };
}

inline fn isHexadecimalDigitChar(char: u8) bool {
    return switch (char) {
        '0'...'9' => true,
        'a'...'f' => true,
        'A'...'F' => true,
        else => false,
    };
}

fn charToken(self: *Tokenizer) Token {
    const kind = Token.getCorrespondingKind(self.peek());
    const start = self.advanceGetIndex();
    return .{ .kind = kind, .start = start, .end = self.index() };
}

fn charEqualsToken(self: *Tokenizer) Token {
    const char = self.peek();
    const start = self.advanceGetIndex();
    if (!self.isAtEnd() and self.peek() == '=') {
        const kind = Token.getCorrespondingKindEquals(char);
        self.advance();
        return .{ .kind = kind, .start = start, .end = self.index() };
    }
    const kind = Token.getCorrespondingKind(char);
    return .{ .kind = kind, .start = start, .end = self.index() };
}

fn escapeSequenceToken(self: *Tokenizer) Token {
    const start = self.advanceGetIndex();
    return .{ .kind = .EscapeSequence, .start = start, .end = self.index() };
}

fn identifierToken(self: *Tokenizer) Token {
    const start = self.index();
    while (!self.isAtEnd() and isIdentifierChar(self.peek())) {
        self.advance();
    }
    const word = self.file.buffer[start..self.index()];
    const kind = Token.keywords.get(word) orelse .Identifier;
    return .{ .kind = kind, .start = start, .end = self.index() };
}

fn underscoreToken(self: *Tokenizer) Token {
    if (self.isNextAtEnd() or !isIdentifierChar(self.peekNext())) {
        const start = self.advanceGetIndex();
        return .{ .kind = .Underscore, .start = start, .end = self.index() };
    }
    return self.identifierToken();
}

fn newLineToken(self: *Tokenizer) Token {
    self.file.line_number += 1;
    self.file.line_start = self.index() + 1;
    const start = self.advanceGetIndex();
    return .{ .kind = .Newline, .start = start, .end = self.index() };
}

fn slashToken(self: *Tokenizer) Token {
    const start = self.advanceGetIndex();
    var kind: Token.Kind = .Slash;
    if (!self.isAtEnd()) {
        switch (self.peek()) {
            '/' => {
                self.advance();
                while (!self.isAtEnd() and self.peek() != '\n') {
                    self.advance();
                }
                kind = .Comment;
            },
            '=' => {
                self.advance();
                kind = .SlashEquals;
            },
            else => {},
        }
    }
    return .{ .kind = kind, .start = start, .end = self.index() };
}

fn numberLiteralToken(self: *Tokenizer) Token {
    var previous: u8 = self.peek();
    const start = self.advanceGetIndex();

    if (previous == '0' and !self.isAtEnd()) {
        const kind_opt: ?Token.Kind = switch (self.peek()) {
            'b', 'B' => self.advanceToEndOfNumber(.IntBinaryLiteral),
            'o', 'O' => self.advanceToEndOfNumber(.IntOctalLiteral),
            'x', 'X' => self.advanceToEndOfNumber(.IntHexadecimalLiteral),
            else => null,
        };
        if (kind_opt) |kind| {
            return .{ .kind = kind, .start = start, .end = self.index() };
        }
    }

    var has_dot = false;
    var has_e = false;
    var has_minus = false;
    while (!self.isAtEnd()) {
        const char = self.peek();
        switch (char) {
            '0'...'9' => {},
            '_' => {
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (previous == '_' or next == '_' or previous == 'e' or previous == 'E' or previous == '-' or next == '-') break;
                if (!isDecimalDigitChar(next)) break;
            },
            '.' => {
                if (has_dot or has_e or self.isNextAtEnd()) break;
                if (!isDecimalDigitChar(self.peekNext())) break;
                has_dot = true;
            },
            'e', 'E' => {
                if (has_e or self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (!isDecimalDigitChar(next) and next != '-') break;
                has_e = true;
            },
            '-' => {
                if (has_minus or !has_e or self.isNextAtEnd()) break;
                if (!isDecimalDigitChar(self.peekNext())) break;
                has_minus = true;
            },
            else => break,
        }
        previous = char;
        self.advance();
    }
    const kind: Token.Kind = switch (has_e) {
        false => if (has_dot) .FloatLiteral else .IntDecimalLiteral,
        true => if (has_minus or has_dot) .FloatScientificLiteral else .IntScientificLiteral,
    };

    return .{ .kind = kind, .start = start, .end = self.index() };
}

fn isValidDigit(char: u8, comptime kind: Token.Kind) bool {
    comptime std.debug.assert(kind == .IntBinaryLiteral or kind == .IntOctalLiteral or kind == .IntHexadecimalLiteral);
    return switch (kind) {
        .IntBinaryLiteral => isBinaryDigitChar(char),
        .IntOctalLiteral => isOctalDigitChar(char),
        .IntHexadecimalLiteral => isHexadecimalDigitChar(char),
        else => unreachable,
    };
}

fn advanceToEndOfNumber(self: *Tokenizer, comptime kind: Token.Kind) Token.Kind {
    comptime std.debug.assert(kind == .IntBinaryLiteral or kind == .IntOctalLiteral or kind == .IntHexadecimalLiteral);
    if (self.isNextAtEnd() or !isValidDigit(self.peekNext(), kind)) {
        return .IntDecimalLiteral;
    }

    var previous = self.peek();
    self.advance();
    while (!self.isAtEnd()) {
        const char = self.peek();
        switch (char) {
            '0'...'1' => {},
            '2'...'7' => switch (kind) {
                .IntOctalLiteral, .IntHexadecimalLiteral => {},
                else => break,
            },
            '9', 'a'...'f', 'A'...'F' => switch (kind) {
                .IntHexadecimalLiteral => {},
                else => break,
            },
            '_' => {
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (previous == '_' or next == '_') break;
                if (!isValidDigit(next, kind)) break;
            },
            else => break,
        }
        previous = char;
        self.advance();
    }

    return kind;
}

fn invalidByte(self: *Tokenizer) Token {
    const start = self.advanceGetIndex();
    return .{ .kind = .InvalidByte, .start = start, .end = self.index() };
}
