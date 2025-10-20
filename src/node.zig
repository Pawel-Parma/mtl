const std = @import("std");

const File = @import("file.zig");
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
    Arguments,

    Expression,

    Scope,
};

pub inline fn token(self: *const Node, file: *File) ?Token {
    const idx = self.token_index orelse return null;
    return file.tokens.items[idx];
}

pub inline fn string(self: *const Node, file: *File) []const u8 {
    return self.token(file).?.string(file);
}
