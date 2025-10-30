const std = @import("std");

const File = @import("file.zig");

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
    ColonEquals,
    DoubleEquals,
    Comma,
    Colon,
    SemiColon,

    ParenLeft,
    ParenRight,
    CurlyLeft,
    CurlyRight,

    IntLiteral,
    FloatLiteral,
    Identifier,

    Pub,
    Var,
    Const,
    Fn,
    Return,

    Newline,
    Comment,
    EscapeSequence,
};

pub const Precedence = enum {
    Lowest,
    Assignment,
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
        .Equals, .ColonEquals => .Assignment,
        .Plus, .Minus => .Sum,
        .Star, .Slash => .Product,
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
        .Plus, .Minus, .Star, .Slash => .Left,
        .Equals => .Right,
        .DoubleEquals, .Comma, .Colon => .Left,
        .ParenLeft => .Left,
        else => .Left,
    };
}

pub const keywords: std.StaticStringMap(Kind) = .initComptime([_]struct { []const u8, Token.Kind }{
    .{ "pub", .Pub },
    .{ "const", .Const },
    .{ "var", .Var },
    .{ "fn", .Fn },
    .{ "return", .Return },
});

pub inline fn len(self: *const Token) usize {
    return self.end - self.start;
}

pub inline fn string(self: *const Token, file: *File) []const u8 {
    return file.buffer[self.start..self.end];
}
