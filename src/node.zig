const std = @import("std");

const File = @import("file.zig");
const Token = @import("token.zig");

const Node = @This();
token_index: ?u32 = null,
children: u32,
kind: Kind,

pub const Kind = enum {
    Expression,

    UnaryMinus,

    BinaryPlus,
    BinaryMinus,
    BinaryStar,
    BinarySlash,
    BinaryPercent,

    BinaryDoubleEquals,
    BinaryBangEquals,
    BinaryGraterThan,
    BinaryGraterEqualsThan,
    BinaryLesserThan,
    BinaryLesserEqualsThan,

    UnaryNot,
    BinaryAnd,
    BinaryOr,
    BinaryCaret,

    Grouping,
    Call,
    IgnoreResult,

    IntLiteral,
    IntBinaryLiteral,
    IntOctalLiteral,
    IntHexadecimalLiteral,
    IntScientificLiteral,
    FloatLiteral,
    FloatScientificLiteral,
    Identifier,
    TrueLiteral,
    FalseLiteral,
    TypeIdentifier,

    ExpressionStatement,
    Mutation,

    Equals,
    PlusEquals,
    MinusEquals,
    StarEquals,
    SlashEquals,
    PercentEquals,
    CaretEquals,

    Public,
    Declaration,
    Function,
    Parameter,
    Parameters,
    Argument,
    Arguments,
    Return,

    Scope,
};

pub inline fn token(self: *const Node, file: *File) ?Token {
    const idx = self.token_index orelse return null;
    return file.tokens.items[idx];
}

pub inline fn string(self: *const Node, file: *File) []const u8 {
    return self.token(file).?.string(file);
}
