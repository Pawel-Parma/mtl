const std = @import("std");

const Token = @This();
kind: Kind,
start: u32,
end: u32,

pub const Kind = enum {
    Invalid,

    Plus,
    Minus,
    Star,
    Slash,

    Equals,
    DoubleEquals,
    Colon,
    SemiColon,
    ColonEquals,

    Comma,

    IntLiteral,
    FloatLiteral,

    Var,
    Const,
    Fn,
    Return,
    Identifier,

    ParenLeft,
    ParenRight,
    CurlyLeft,
    CurlyRight,

    Newline,
    Comment,
    EscapeSequence,
};

pub const Precedence = enum(u8) {
    Lowest = 0,
    Assignment,
    Sum,
    Product,
    Prefix,
    Suffix,

    pub inline fn toInt(self: Precedence) u8 {
        return @intFromEnum(self);
    }
};

pub inline fn precedence(self: *const Token) Precedence {
    return switch (self.kind) {
        .Equals, .ColonEquals => .Assignment,
        .Plus, .Minus => .Sum,
        .Star, .Slash => .Product,
        .ParenLeft => .Suffix,
        else => .Lowest,
    };
}

pub const keywords: std.StaticStringMap(Kind) = .initComptime([_]struct { []const u8, Token.Kind }{
    .{ "const", .Const },
    .{ "var", .Var },
    .{ "fn", .Fn },
    .{ "return", .Return },
});

pub inline fn len(self: *const Token) usize {
    return self.end - self.start;
}

pub inline fn string(self: *const Token, buffer: []const u8) []const u8 {
    return buffer[self.start..self.end];
}
