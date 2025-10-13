const std = @import("std");

const Token = @import("token.zig");

const Node = @This();
kind: Kind,
children: u32,
token_index: ?u32 = null,

pub const Kind = enum {
    UnaryMinus,

    BinaryPlus,
    BinaryMinus,
    BinaryStar,
    BinarySlash,

    Call,

    IntLiteral,
    FloatLiteral,

    Identifier,
    TypeIdentifier,

    Return,

    Declaration,
    Function,
    Parameter,
    Parameters,

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
