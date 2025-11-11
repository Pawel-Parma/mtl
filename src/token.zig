const std = @import("std");

const File = @import("file.zig");

const Token = @This();
start: u32,
end: u32,
kind: Kind,

pub const Kind = enum {
    InvalidByte,
    EscapeSequence,
    Eof,
    Newline,
    Comment,

    Pub,
    Var,
    Const,

    Colon,
    Equals,
    ColonEquals,

    IntLiteral,
    IntBinaryLiteral,
    IntOctalLiteral,
    IntHexadecimalLiteral,
    IntScientificLiteral,
    FloatLiteral,
    FloatScientificLiteral,
    Identifier,

    Plus,
    PlusEquals,
    Minus,
    MinusEquals,
    Star,
    StarEquals,
    Slash,
    SlashEquals,
    Percent,
    PercentEquals,

    DoubleEquals,
    BangEquals,
    GraterThan,
    GraterEqualsThan,
    LesserThan,
    LesserEqualsThan,

    And,
    Not,
    Or,
    TrueLiteral,
    FalseLiteral,
    Caret,
    CaretEquals,

    ParenLeft,
    ParenRight,
    CurlyLeft,
    CurlyRight,

    Bang,

    Fn,
    Return,

    Comma,
    SemiColon,
    Underscore,
};

pub const Precedence = enum {
    Lowest,
    Xor,
    Or,
    And,
    Equality,
    Sum,
    Product,
    Prefix,
    Suffix,

    pub inline fn lessThan(self: Precedence, right: Precedence) bool {
        return @intFromEnum(self) < @intFromEnum(right);
    }
};

pub inline fn precedence(self: *const Token) Precedence {
    return switch (self.kind) {
        .Or => .Or,
        .Caret => .Xor,
        .And => .And,
        .DoubleEquals, .BangEquals, .GraterThan, .GraterEqualsThan, .LesserThan, .LesserEqualsThan => .Equality,
        .Plus, .Minus => .Sum,
        .Star, .Slash, .Percent => .Product,
        .Not => .Prefix,
        .ParenLeft => .Suffix,
        else => .Lowest,
    };
}

pub const Associativity = enum {
    Left,
    Right,
};

pub inline fn associativity(self: *const Token) Associativity {
    return switch (self.kind) {
        .Plus, .Minus, .Star, .Slash, .Percent => .Left,
        .DoubleEquals, .BangEquals, .GraterThan, .GraterEqualsThan, .LesserThan, .LesserEqualsThan => .Left,
        .And, .Or, .Caret => .Left,
        .Not => .Right,
        .ParenLeft => .Left,
        else => .Left,
    };
}

pub const keywords: std.StaticStringMap(Kind) = .initComptime([_]struct { []const u8, Token.Kind }{
    .{ "pub", .Pub },
    .{ "const", .Const },
    .{ "var", .Var },
    .{ "true", .TrueLiteral },
    .{ "false", .FalseLiteral },
    .{ "and", .And },
    .{ "or", .Or },
    .{ "not", .Not },
    .{ "fn", .Fn },
    .{ "return", .Return },
});

pub fn getCorrespondingKind(char: u8) Token.Kind {
    return switch (char) {
        ';' => .SemiColon,
        ',' => .Comma,
        '(' => .ParenLeft,
        ')' => .ParenRight,
        '{' => .CurlyLeft,
        '}' => .CurlyRight,
        '-' => .Minus,
        '+' => .Plus,
        '*' => .Star,
        '%' => .Percent,
        ':' => .Colon,
        '=' => .Equals,
        '>' => .GraterThan,
        '<' => .LesserThan,
        '^' => .Caret,
        '!' => .Bang,
        else => unreachable,
    };
}

pub fn getCorrespondingKindEquals(char: u8) Token.Kind {
    return switch (char) {
        '+' => .PlusEquals,
        '-' => .MinusEquals,
        '*' => .StarEquals,
        '%' => .PercentEquals,
        ':' => .ColonEquals,
        '=' => .DoubleEquals,
        '>' => .GraterEqualsThan,
        '<' => .LesserEqualsThan,
        '^' => .CaretEquals,
        '!' => .BangEquals,
        else => unreachable,
    };
}

pub inline fn len(self: *const Token) usize {
    return self.end - self.start;
}

pub inline fn string(self: *const Token, file: *File) []const u8 {
    return file.buffer[self.start..self.end];
}
