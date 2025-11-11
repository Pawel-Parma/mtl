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
        'a'...'z', 'A'...'Z' => self.identifierToken(),
        '_' => self.underscoreToken(),
        '0'...'9' => self.numberLiteralToken(),
        '\n' => self.newLineToken(),
        '/' => self.slashToken(),
        ';', ',', '(', ')', '{', '}' => self.oneCharToken(),
        '+', '-', '*', '%', ':', '=', '!', '>', '<', '^' => self.charEqualsToken(),
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

inline fn peekNext(self: *Tokenizer) u8 {
    return self.file.buffer[self.file.position + 1];
}

inline fn peekN(self: *Tokenizer, n: u32) u8 {
    return self.file.buffer[self.file.position + n];
}

inline fn isAtEnd(self: *Tokenizer) bool {
    return self.file.position >= self.file.buffer.len;
}

inline fn isNextAtEnd(self: *Tokenizer) bool {
    return self.file.position + 1 >= self.file.buffer.len;
}

inline fn isNAtEnd(self: *Tokenizer, n: u32) bool {
    return self.file.position + n >= self.file.buffer.len;
}

inline fn isIdentifierChar(char: u8) bool {
    return switch (char) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn oneCharToken(self: *Tokenizer) Token {
    const kind = Token.getCorrespondingKind(self.peek());
    const start = self.advanceGetIndex();
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn charEqualsToken(self: *Tokenizer) Token {
    const char = self.peek();
    const start = self.advanceGetIndex();
    if (!self.isAtEnd() and self.peek() == '=') {
        const kind = Token.getCorrespondingKindEquals(char);
        self.advance();
        return .{ .kind = kind, .start = start, .end = self.file.position };
    }
    const kind = Token.getCorrespondingKind(char);
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn newLineToken(self: *Tokenizer) Token {
    self.file.line_number += 1;
    self.file.line_start = self.file.position + 1;
    const start = self.advanceGetIndex();
    return .{ .kind = .Newline, .start = start, .end = self.file.position };
}

fn escapeSequenceToken(self: *Tokenizer) Token {
    const start = self.advanceGetIndex();
    return .{ .kind = .EscapeSequence, .start = start, .end = self.file.position };
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
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn numberLiteralToken(self: *Tokenizer) Token {
    var previous: u8 = self.peek();
    const start = self.advanceGetIndex();

    if (previous == '0' and !self.isAtEnd()) {
        switch (self.peek()) {
            'b', 'B' => {
                if (self.isNextAtEnd() or (self.peekNext() < '0' or self.peekNext() > '1')) {
                    return .{ .kind = .IntLiteral, .start = start, .end = self.file.position };
                }
                self.advanceToEndOfNumberRange('0', '1');
                return .{ .kind = .IntBinaryLiteral, .start = start, .end = self.file.position };
            },
            'o', 'O' => {
                if (self.isNextAtEnd() or (self.peekNext() < '0' or self.peekNext() > '8')) {
                    return .{ .kind = .IntLiteral, .start = start, .end = self.file.position };
                }
                self.advanceToEndOfNumberRange('0', '8');
                return .{ .kind = .IntOctalLiteral, .start = start, .end = self.file.position };
            },
            'x', 'X' => {
                const next = self.peekNext();
                if (self.isNextAtEnd() or !((next >= '0' and next <= '9') or (next >= 'a' and next <= 'f') or (next >= 'A' and next <= 'F'))) {
                    return .{ .kind = .IntLiteral, .start = start, .end = self.file.position };
                }
                self.advanceToEndOfNumberHex();
                return .{ .kind = .IntHexadecimalLiteral, .start = start, .end = self.file.position };
            },
            else => {},
        }
    }

    var has_dot = false;
    var has_e = false;
    var has_minus = false;
    var is_float = false;
    while (!self.isAtEnd()) {
        const char = self.peek();
        switch (char) {
            '0'...'9' => {},
            '_' => {
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (previous == '_' or next == '_' or previous == 'e' or previous == 'E' or previous == '-' or next == '-') break;
                if (next < '0' or next > '9') break;
            },
            '.' => {
                if (has_dot or has_e) break;
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (next < '0' or next > '9') break;
                has_dot = true;
                is_float = true;
            },
            'e', 'E' => {
                if (has_e) break;
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if ((next < '0' or next > '9') and next != '-') break;
                if (next == '-') {
                    if (self.isNAtEnd(2)) break;
                    const next2 = self.peekN(2);
                    if (next2 < '0' or next2 > '9') break;
                }
                has_e = true;
            },
            '-' => {
                if (has_minus or !has_e) break;
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (next < '0' or next > '9') break;
                has_minus = true;
                is_float = true;
            },
            else => break,
        }
        previous = char;
        self.advance();
    }
    const kind: Token.Kind = switch (has_e) {
        false => if (is_float) .FloatLiteral else .IntLiteral,
        true => if (is_float) .FloatScientificLiteral else .IntScientificLiteral,
    };

    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn advanceToEndOfNumberRange(self: *Tokenizer, comptime range_lower: u8, comptime range_upper: u8) void {
    var previous = self.peek();
    self.advance();
    while (!self.isAtEnd()) {
        const char = self.peek();
        switch (char) {
            range_lower...range_upper => {},
            '_' => {
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (previous == '_' or next == '_') break;
                if (next < range_lower or next > range_upper) break;
            },
            else => break,
        }
        previous = char;
        self.advance();
    }
}

fn advanceToEndOfNumberHex(self: *Tokenizer) void {
    var previous = self.peek();
    self.advance();
    while (!self.isAtEnd()) {
        const char = self.peek();
        switch (char) {
            '0'...'9', 'a'...'f', 'A'...'F' => {},
            '_' => {
                if (self.isNextAtEnd()) break;
                const next = self.peekNext();
                if (previous == '_' or next == '_') break;
                if (!((next >= '0' and next <= '9') or (next >= 'a' and next <= 'f') or (next >= 'A' and next <= 'F'))) break;
            },
            else => break,
        }
        previous = char;
        self.advance();
    }
}

fn identifierToken(self: *Tokenizer) Token {
    const start = self.file.position;
    while (!self.isAtEnd() and isIdentifierChar(self.peek())) {
        self.advance();
    }
    const word = self.file.buffer[start..self.file.position];
    const kind = Token.keywords.get(word) orelse .Identifier;
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn underscoreToken(self: *Tokenizer) Token {
    if (self.isNextAtEnd() or !isIdentifierChar(self.peekNext())) {
        const start = self.advanceGetIndex();
        return .{ .kind = .Underscore, .start = start, .end = self.file.position };
    }
    return self.identifierToken();
}

fn unsupportedByte(self: *Tokenizer) Token {
    const start = self.file.position;
    self.advance();
    return .{ .kind = .InvalidByte, .start = start, .end = self.file.position };
}
