const std = @import("std");
const exit = @import("exit.zig").exit;

const Tokenizer = @This();
allocator: std.mem.Allocator,
input: []const u8,
position: usize,
tokens: std.ArrayList(Token),

pub const Token = struct {
    position_start: usize,
    position_end: usize,
    kind: Kind,
};

const Kind = enum {
    NUMBER_LITERAL,
    VAR,
    CONST,
    ASSIGN,
    SEMICOLON,
    IDENTIFIER,
};

const keyword_map = [_]struct {
    name: []const u8,
    kind: Kind,
}{
    .{ .name = "var", .kind = Kind.VAR },
    .{ .name = "const", .kind = Kind.CONST },
};

pub fn init(allocator: std.mem.Allocator, input: []const u8) Tokenizer {
    return .{
        .allocator = allocator,
        .input = input,
        .position = 0,
        .tokens = .empty,
    };
}

pub fn tokenize(self: *Tokenizer) !void {
    while (self.position < self.input.len) {
        switch (self.input[self.position]) {
            ' ', '\r', '\n', '\t' => self.whitespace(),
            ';' => try self.semicolon(),
            '=' => try self.equals_sign(),
            '0'...'9' => try self.number_literal(),
            'a'...'z', 'A'...'Z' => try self.keywords_and_identifiers(),
            else => self.unsupported_character(),
        }
    }
}

fn whitespace(self: *Tokenizer) void {
    self.position += 1;
}

fn semicolon(self: *Tokenizer) !void {
    try self.tokens.append(self.allocator, .{ .kind = Kind.SEMICOLON, .position_start = self.position, .position_end = self.position + 1 });
    self.position += 1;
}

fn equals_sign(self: *Tokenizer) !void {
    try self.tokens.append(self.allocator, .{ .kind = Kind.ASSIGN, .position_start = self.position, .position_end = self.position + 1 });
    self.position += 1;
}

fn number_literal(self: *Tokenizer) !void {
    const start = self.position;
    while (self.position < self.input.len and self.input[self.position] >= '0' and self.input[self.position] <= '9') {
        self.position += 1;
    }
    try self.tokens.append(self.allocator, .{ .kind = Kind.NUMBER_LITERAL, .position_start = start, .position_end = self.position });
}

fn keywords_and_identifiers(self: *Tokenizer) !void {
    const start = self.position;
    while (self.position < self.input.len) : (self.position += 1) {
        const c = self.input[self.position];
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')) continue;
        break;
    }
    const word = self.input[start..self.position];
    const kind = keyword_lookup(word);

    try self.tokens.append(self.allocator, .{
        .kind = kind,
        .position_start = start,
        .position_end = self.position,
    });
}

fn keyword_lookup(word: []const u8) Kind {
    inline for (keyword_map) |entry| {
        if (std.mem.eql(u8, word, entry.name)) return entry.kind;
    }
    return Kind.IDENTIFIER;
}

fn unsupported_character(self: *Tokenizer) noreturn {
    std.debug.print("Unexpected character: {d}\n", .{self.input[self.position]});
    exit(102);
}
