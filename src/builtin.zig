const std = @import("std");

pub const Kind = enum {
    Print,
    Typeof,
};

const builtins = std.StaticStringMap(Kind).initComptime(.{
    .{ "print", .Print },
    .{ "typeof", .Typeof },
});

pub fn lookup(name: []const u8) ?Kind {
    return builtins.get(name);
}
