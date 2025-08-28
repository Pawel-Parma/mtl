const std = @import("std");
const core = @import("core.zig");


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
        STAR,
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
        CURLY_LEFT,
        CURLY_RIGHT
    };

    pub const Precedence = enum(u8) {
        LOWEST = 0,
        ASSIGNMENT,
        SUM,
        PRODUCT,
        PREFIX,
        SUFFIX,

        pub inline fn toInt(self: *const Precedence) u8 {
            return @intFromEnum(self.*);
        }
    };

    pub fn getPrecedence(self: *const Token) Precedence {
        return switch (self.kind) {
            .EQUALS, .COLON_EQUALS => .ASSIGNMENT,
            .PLUS, .MINUS => .SUM,
            .STAR, .SLASH => .PRODUCT,
            .PAREND_LEFT => .SUFFIX,
            else => .LOWEST,
        };
    }

    pub inline fn getName(self: *const Token, buffer: []const u8) []const u8 {
        return buffer[self.start..self.end];
    }
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

pub fn tokenize(self: *Tokenizer) std.mem.Allocator.Error!void {
    // TODO: more flexible tokenizer, support whitespace between tokens in more places
    try self.tokens.ensureTotalCapacityPrecise(self.allocator, 16);
    while (self.position < self.input.len) {
        switch (self.input[self.position]) {
            ' ', '\r', '\n', '\t' => self.whitespace(),
            '+' => try self.oneCharToken(.PLUS),
            '-' => try self.oneCharToken(.MINUS),
            '*' => try self.oneCharToken(.STAR),
            '/' => try self.slash(),
            '(' => try self.oneCharToken(.PAREND_LEFT),
            ')' => try self.oneCharToken(.PAREND_RIGHT),
            '{' => try self.oneCharToken(.CURLY_LEFT),
            '}' => try self.oneCharToken(.CURLY_RIGHT),
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
    if (self.input[self.position + 1] == '/') {
        while (self.position < self.input.len and self.input[self.position] != '\n') {
            self.position += 1;
        }
        self.position += 2;
        return;
    }
    try self.tokens.append(self.allocator, .{ .kind = .SLASH, .start = self.position, .end = self.position + 1 });
    self.position += 1;
}

inline fn numberLiteral(self: *Tokenizer) !void {
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
    // TODO: make the source code utf-8 encoded as currently only the first codepoint of unsupported characters is reported
    // TODO: add nice error messages, everywhere
    var line_num: usize = 1;
    var line_start: usize = 0;
    for (self.input[0..self.position], 0..) |c, i| {
        if (c == '\n') {
            line_num += 1;
            line_start = i + 1;
        }
    }

    core.rprint("Error: line {d} - column {d}\n", .{ line_num, self.position - line_start + 1 });
    core.rprint("Unsupported character: {d}\n\n", .{self.input[self.position]});
    core.exit(101);
}
