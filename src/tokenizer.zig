const std = @import("std");
const core = @import("core.zig");

const Token = @import("token.zig");

const Tokenizer = @This();
allocator: std.mem.Allocator,
buffer: []const u8,
position: usize,
line_number: usize,
line_start: usize,
failed: bool,
tokens: std.ArrayList(Token),

pub const Error = error{
    TokenizeFailed,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, buffer: []const u8) Tokenizer {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .position = 0,
        .line_number = 1,
        .line_start = 0,
        .failed = false,
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
        switch (self.peek()) {
            ' ', '\t', '\r', '\x0B', '\x0C' => _ = self.advance(),
            '\n' => self.advanceLine(),
            'a'...'z', 'A'...'Z' => try self.identifierToken(),
            '0'...'9' => try self.numberLiteralToken(),
            ';' => try self.oneCharToken(.Semicolon),
            '-' => try self.oneCharToken(.Minus),
            '+' => try self.oneCharToken(.Plus),
            '*' => try self.oneCharToken(.Star),
            '/' => try self.slashToken(),
            '(' => try self.oneCharToken(.ParenLeft),
            ')' => try self.oneCharToken(.ParenRight),
            '{' => try self.oneCharToken(.CurlyLeft),
            '}' => try self.oneCharToken(.CurlyRight),
            ':' => try self.twoCharToken(.Colon, '=', .ColonEquals),
            '=' => try self.twoCharToken(.Equals, '=', .DoubleEquals),
            else => self.unsupportedCharacter(),
        }
    }
    if (self.failed) {
        return error.TokenizeFailed;
    }
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

inline fn appendToken(self: *Tokenizer, kind: Token.Kind, start: usize, end: usize) !void {
    try self.tokens.append(self.allocator, .{ .kind = kind, .start = start, .end = end });
}

fn oneCharToken(self: *Tokenizer, kind: Token.Kind) !void {
    try self.appendToken(kind, self.position, self.position + 1);
    _ = self.advance();
}

fn twoCharToken(self: *Tokenizer, kind_one: Token.Kind, char_two: u8, kind_two: Token.Kind) !void {
    const start = self.advance();
    if (!self.isAtEnd() and self.peek() == char_two) {
        _ = self.advance();
        try self.appendToken(kind_two, start, self.position);
        return;
    }
    try self.appendToken(kind_one, start, self.position);
}

fn slashToken(self: *Tokenizer) !void {
    const start = self.advance();
    if (!self.isAtEnd() and self.peek() == '/') {
        _ = self.advance();
        while (!self.isAtEnd() and self.peek() != '\n') {
            _ = self.advance();
        }
        return;
    }
    try self.appendToken(.Slash, start, self.position);
}

fn numberLiteralToken(self: *Tokenizer) !void {
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

    try self.appendToken(kind, start, self.position);
}

fn identifierToken(self: *Tokenizer) !void {
    const start = self.position;
    while (!self.isAtEnd() and self.isIdentifierChar()) {
        _ = self.advance();
    }
    const word = self.buffer[start..self.position];
    const kind = Token.KeywordMap.get(word) orelse .Identifier;

    try self.appendToken(kind, start, self.position);
}

// fn unsupportedCharacter(self: *Tokenizer) void {
//     // TODO: make the source code utf-8 encoded as currently only the first codepoint of unsupported characters is reported
//     self.failed = true;
//     _ = self.advance();
//     const line = self.line_number;
//     const col = self.position - self.line_start;

//     core.rprint("Error: unsupported character at line {d}, column {d}\n", .{ line, col });
//     core.rprint("Character: '{c}' (0x{x})\n\n", .{ self.peek(), self.peek() });
// }
fn unsupportedCharacter(self: *Tokenizer) void {
    self.failed = true;
    core.rprint("{c}\n", .{self.peek()});

    const len = std.unicode.utf8ByteSequenceLength(self.peek()) catch unreachable;
    // Advance by the actual number of bytes consumed
    core.rprint("Advancing by {d} bytes\n", .{ len });
    self.position += len;

    const line = self.line_number;
    const col = self.position - self.line_start;

    core.rprint("Error: unsupported character at line {d}, column {d}\n", .{ line, col });
    core.dprintn("\n");
    core.dprint("{s}\n", .{self.buffer});
    core.dprintn("\n");
    core.rprint("1111: {s}\n", .{self.buffer[self.position - 5.. self.position + 5]});
    core.rprint("Character: '{s}' \n", .{self.buffer[self.position - len.. self.position]});
}
