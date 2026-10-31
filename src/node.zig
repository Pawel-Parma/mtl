const std = @import("std");

const File = @import("file.zig");
const Token = @import("token.zig");

const Node = @This();
token_index: ?u32 = null,
children: u32,
kind: Kind,

pub const Kind = enum {
    Expression,
    TypeExpression,

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
    BinaryXor,

    Grouping,
    Call,
    IgnoreResult,

    IntBinaryLiteral,
    IntOctalLiteral,
    IntDecimalLiteral,
    IntHexadecimalLiteral,
    IntScientificLiteral,
    FloatLiteral,
    FloatScientificLiteral,
    BoolLiteral,
    Identifier,

    ExpressionStatement,
    Mutation,

    Equals,
    PlusEquals,
    MinusEquals,
    StarEquals,
    SlashEquals,
    PercentEquals,

    Public,
    Declaration,
    Function,
    Parameter,
    Parameters,
    Argument,
    Arguments,
    Return,

    Scope,

    Builtin,

    pub fn fromTokenKind(kind: Token.Kind) Kind {
        return switch (kind) {
            .Identifier => .Identifier,
            .IntDecimalLiteral => .IntDecimalLiteral,
            .IntBinaryLiteral => .IntBinaryLiteral,
            .IntOctalLiteral => .IntOctalLiteral,
            .IntHexadecimalLiteral => .IntHexadecimalLiteral,
            .IntScientificLiteral => .IntScientificLiteral,
            .FloatLiteral => .FloatLiteral,
            .FloatScientificLiteral => .FloatScientificLiteral,
            .BoolLiteral => .BoolLiteral,

            .Not => .UnaryNot,

            .Plus => .BinaryPlus,
            .Star => .BinaryStar,
            .Slash => .BinarySlash,
            .Percent => .BinaryPercent,
            .DoubleEquals => .BinaryDoubleEquals,
            .BangEquals => .BinaryBangEquals,
            .GraterThan => .BinaryGraterThan,
            .GraterEqualsThan => .BinaryGraterEqualsThan,
            .LesserThan => .BinaryLesserThan,
            .LesserEqualsThan => .BinaryLesserEqualsThan,
            .And => .BinaryAnd,
            .Or => .BinaryOr,
            .Xor => .BinaryXor,

            else => unreachable,
        };
    }
};

pub inline fn token(self: *const Node, file: *File) ?Token {
    const idx = self.token_index orelse return null;
    return file.tokens.items[idx];
}

pub inline fn string(self: *const Node, file: *File) []const u8 {
    return self.token(file).?.string(file);
}
