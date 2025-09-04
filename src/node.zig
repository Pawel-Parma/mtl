const std = @import("std");
const Token = @import("token.zig");

const Node = @This();
kind: Kind,
children: std.ArrayList(Node),
token_index: ?usize = null,

pub const Kind = enum {
    Keyword,
    Identifier,
    TypeIdentifier,
    Declaration,
    Expression,
    BinaryOperator,
    UnaryOperator,
    NumberLiteral,
    Scope,
};

pub inline fn token(self: *const Node, tokens: []const Token) ?Token {
    if (self.token_index) |idx| {
        return tokens[idx];
    } else {
        return null;
    }
}
