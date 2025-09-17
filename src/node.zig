const std = @import("std");
const core = @import("core.zig");
const Token = @import("token.zig");

const Node = @This();
kind: Kind,
// TODO: make children start end instead of slice
children: []Node,
token_index: ?usize = null,

pub const Kind = enum {
    UnaryOperator,
    BinaryOperator,

    IntLiteral,
    FloatLiteral,

    Identifier,
    TypeIdentifier,

    Keyword,
    Declaration,

    Expression,

    Scope,
};

pub inline fn token(self: *const Node, tokens: []const Token) ?Token {
    const idx = self.token_index orelse return null;
    return tokens[idx];
}

pub inline fn string(self: *const Node, buffer: []const u8, tokens: []const Token) []const u8 {
    return self.token(tokens).?.string(buffer);
}

pub fn dprint(self: *const Node, buffer: []const u8, tokens: []const Token, depth: usize) void {
    for (0..depth) |_| {
        core.dprint("  ", .{});
    }
    core.dprint("{any} (token_index={any})", .{ self.kind, self.token_index });
    if (self.token(tokens)) |t| {
        core.dprint(" (token.kind={any}) (token.string=\"{s}\")", .{ t.kind, t.string(buffer) });
    }
    core.dprint("\n", .{});

    for (self.children) |child| {
        child.dprint(buffer, tokens, depth + 1);
    }
}
