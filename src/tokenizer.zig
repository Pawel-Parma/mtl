const std = @import("std");
const exit = @import("exit.zig").exit;

const Tokenizer = @This();
allocator: std.mem.Allocator,
input: []const u8,
position: usize,
tokens: std.ArrayList(Token),

pub const Token = struct {
    start: usize,
    end: usize,
    kind: Kind,

    pub const Kind = enum {
        PLUS,
        MINUS,
        TIMES,
        SLASH,
        NUMBER_LITERAL,
        VAR,
        CONST,
        DOUBLE_EQALS,
        EQUALS,
        COLON,
        PAREND_LEFT,
        PAREND_RIGHT,
        COLON_EQUALS,
        SEMICOLON,
        IDENTIFIER,
    };
};

const keyword_map = [_]struct {
    name: []const u8,
    kind: Token.Kind,
}{
    .{ .name = "var", .kind = .VAR },
    .{ .name = "const", .kind = .CONST },
};

pub fn init(allocator: std.mem.Allocator, input: []const u8) Tokenizer {
    return .{
        .allocator = allocator,
        .input = input,
        .position = 0,
        .tokens = .empty,
    };
}

pub fn deinit(self: *Tokenizer) void {
    self.tokens.deinit(self.allocator);
}

pub fn tokenize(self: *Tokenizer) !void {
    try self.tokens.ensureTotalCapacityPrecise(self.allocator, 16);
    while (self.position < self.input.len) {
        switch (self.input[self.position]) {
            ' ', '\r', '\n', '\t' => self.whitespace(),
            '+' => try self.oneCharToken(.PLUS),
            '-' => try self.oneCharToken(.MINUS),
            '*' => try self.oneCharToken(.TIMES),
            '/' => try self.slash(),
            '(' => try self.oneCharToken(.PAREND_LEFT),
            ')' => try self.oneCharToken(.PAREND_RIGHT),
            ':' => try self.twoCharToken(.COLON, '=', .COLON_EQUALS),
            ';' => try self.oneCharToken(.SEMICOLON),
            '=' => try self.twoCharToken(.EQUALS, '=', .DOUBLE_EQALS),
            '0'...'9' => try self.numberLiteral(),
            'a'...'z', 'A'...'Z' => try self.keywordsAndIdentifiers(),
            else => self.unsupportedCharacter(),
        }
    }
}

inline fn whitespace(self: *Tokenizer) void {
    self.position += 1;
}

inline fn oneCharToken(self: *Tokenizer, kind: Token.Kind) !void {
    try self.tokens.append(self.allocator, .{ .kind = kind, .start = self.position, .end = self.position + 1 });
    self.position += 1;
}

inline fn twoCharToken(self: *Tokenizer, kind_one: Token.Kind, char_two: u8, kind_two: Token.Kind) !void {
    if (self.input[self.position + 1] == char_two) {
        try self.tokens.append(self.allocator, .{ .kind = kind_two, .start = self.position, .end = self.position + 2 });
        self.position += 2;
        return;
    }
    try self.tokens.append(self.allocator, .{ .kind = kind_one, .start = self.position, .end = self.position + 1 });
    self.position += 1;
}

inline fn slash(self: *Tokenizer) !void {
    const pc = self.input[self.position + 1];
    if (pc == '/') {
        self.position += 2;
        while (self.position < self.input.len and self.input[self.position] != '\n') {
            self.position += 1;
        }
        return;
    } else if (pc == '*') {
        while (self.position + 1 < self.input.len) : (self.position += 1) {
            if (self.input[self.position] == '*' and self.input[self.position + 1] == '/') {
                self.position += 2;
                return;
            }
        }
    }
    try self.tokens.append(self.allocator, .{ .kind = .SLASH, .start = self.position, .end = self.position + 1 });
    self.position += 1;
}

fn numberLiteral(self: *Tokenizer) !void {
    const start = self.position;
    while (self.position < self.input.len and self.input[self.position] >= '0' and self.input[self.position] <= '9') {
        self.position += 1;
    }
    try self.tokens.append(self.allocator, .{ .kind = .NUMBER_LITERAL, .start = start, .end = self.position });
}

fn keywordsAndIdentifiers(self: *Tokenizer) !void {
    const start = self.position;
    while (self.position < self.input.len) : (self.position += 1) {
        const c = self.input[self.position];
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')) continue;
        break;
    }
    const word = self.input[start..self.position];
    const kind = keywordLookup(word);

    try self.tokens.append(self.allocator, .{
        .kind = kind,
        .start = start,
        .end = self.position,
    });
}

fn keywordLookup(word: []const u8) Token.Kind {
    inline for (keyword_map) |entry| {
        if (std.mem.eql(u8, word, entry.name)) return entry.kind;
    }
    return .IDENTIFIER;
}

fn unsupportedCharacter(self: *Tokenizer) noreturn {
    std.debug.print("Unexpected character: {d}\n", .{self.input[self.position]});
    exit(102);
}
