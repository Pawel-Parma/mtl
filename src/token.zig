const std = @import("std");

const Token = @This();
kind: Kind,
start: usize,
end: usize,

pub const Kind = enum {
    Plus,
    Minus,
    Star,
    Slash,

    Equals,
    DoubleEquals,
    Colon,
    ColonEquals,

    IntLiteral,
    FloatLiteral,

    Var,
    Const,
    Identifier,

    ParenLeft,
    ParenRight,
    CurlyLeft,
    CurlyRight,

    Semicolon,
};

pub const KeywordMap: std.StaticStringMap(Kind) = .initComptime([_]struct { []const u8, Token.Kind }{
    .{ "const", .Const },
    .{ "var", .Var },
});

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

pub inline fn string(self: *const Token, buffer: []const u8) []const u8 {
    return buffer[self.start..self.end];
}

pub inline fn precedence(self: *const Token) Precedence {
    return switch (self.kind) {
        .Equals, .ColonEquals => .Assignment,
        .Plus, .Minus => .Sum,
        .Star, .Slash => .Product,
        .ParenLeft => .Suffix,
        else => .Lowest,
    };
}
