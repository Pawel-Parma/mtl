const std = @import("std");
const Token = @import("token.zig");

const Node = @This();
kind: Kind,
children: std.ArrayList(Node),
token_index: ?usize = null,

pub const Kind = enum {
    Invalid,

    UnaryOperator,
    BinaryOperator,

    NumberLiteral,

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
