const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");
const File = @import("file.zig");

const Tokenizer = @This();
allocator: std.mem.Allocator,
file: *File,

pub const Error = error{
    TokenizingFailed,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, file: *File) Tokenizer {
    return .{
        .allocator = allocator,
        .file = file,
    };
}

pub fn tokenize(self: *Tokenizer) Error!void {
    try self.file.ensureTokensCapacity();
    while (!self.isAtEnd()) {
        const token = self.nextToken() orelse continue;
        try self.file.tokens.append(self.allocator, token);
    }
    if (!self.success) {
        return Error.TokenizingFailed;
    }
    self.file.printTokens();
}

pub fn nextToken(self: *Tokenizer) ?Token {
    return switch (self.peek()) {
        ' ', '\t', '\r', '\x0B', '\x0C' => blk: {
            _ = self.advance();
            break :blk null;
        },
        'a'...'z', 'A'...'Z' => self.identifierToken(),
        '0'...'9' => self.numberLiteralToken(),
        '\n' => self.newLineToken(),
        ';' => self.oneCharToken(.Eol),
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
        else => self.unsupportedCharacter(),
    };
}

inline fn advance(self: *Tokenizer) usize {
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
    const c = self.peek();
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn oneCharToken(self: *Tokenizer, kind: Token.Kind) Token {
    const start = self.advance();
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn twoCharToken(self: *Tokenizer, kind_one: Token.Kind, char_two: u8, kind_two: Token.Kind) Token {
    const start = self.advance();
    if (!self.isAtEnd() and self.peek() == char_two) {
        _ = self.advance();
        return .{ .kind = kind_two, .start = start, .end = self.file.position };
    }
    return .{ .kind = kind_one, .start = start, .end = self.file.position };
}

fn newLineToken(self: *Tokenizer) ?Token {
    self.file.line_number += 1;
    self.file.line_start = self.file.position + 1;
    _ = self.advance();
    return null; // TODO: self.oneCharToken(.Eol);
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
    return .{ .kind = .Slash, .start = start, .end = self.file.position };
}

fn numberLiteralToken(self: *Tokenizer) Token {
    const start = self.file.position;
    var has_dot = false;
    var is_float = false;
    while (!self.isAtEnd()) {
        switch (self.peek()) {
            '0'...'9', '_' => {
                _ = self.advance();
                if (has_dot) {
                    is_float = true;
                }
            },
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
    const kind: Token.Kind = if (is_float) .FloatLiteral else .IntLiteral;
    return .{ .kind = kind, .start = start, .end = self.file.position };
}

fn identifierToken(self: *Tokenizer) Token {
    const start = self.file.position;
    while (!self.isAtEnd() and self.isIdentifierChar()) {
        _ = self.advance();
    }
    const word = self.file.buffer[start..self.file.position];
    const kind = Token.KeywordMap.get(word) orelse .Identifier;
    return .{ .kind = kind, .start = start, .end = self.position };
}

fn unsupportedCharacter(self: *Tokenizer) Token {
    self.file.success = false;
    const len = std.unicode.utf8ByteSequenceLength(self.peek()) catch 1;
    self.file.position += len;

    const column_number = self.file.position - self.file.line_start - len;
    const line = core.getLine(self.file.buffer, self.file.line_start, self.file.position, self.file.buffer.len - self.file.position);

    core.printSourceLine("encountered unsupported character\n", .{}, self.file_path, self.line_number, column_number, line, 1);
    return .{ .kind = .Invalid, .start = self.position - len, .end = self.position };
}
