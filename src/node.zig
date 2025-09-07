const std = @import("std");
const Token = @import("token.zig");

const Node = @This();
kind: Kind,
// TODO: make children start end instead of slice
children: []Node,
token_index: ?usize = null,

pub const Kind = enum {
    UnaryOperator,
    BinaryOperator,

    NumberLiteral,

    Identifier,
    TypeIdentifier,

    Keyword,
    ConstDeclaration,
    VarDeclaration,

    Expression,

    Scope,
};

pub inline fn token(self: *const Node, tokens: []const Token) ?Token {
    const idx = self.token_index orelse return null;
    return tokens[idx];
}
