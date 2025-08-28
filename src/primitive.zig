const std = @import("std");

pub const Type = enum {
    I8, I16, I32, I64, I128,
    U8, U16, U32, U64, U128,
    F16, F32, F64, F80, F128,
    Type, ComptimeInt, ComptimeFloat, 
    DebugVal,

    pub inline fn toInt(self: Type) u8 {
        return @intFromEnum(self);
    }
};

pub const entries = [_]struct {
    name: []const u8,
    kind: Type,
}{
    .{ .name = "i8", .kind = .I8 },     .{ .name = "i16", .kind = .I16 },                  .{ .name = "i32", .kind = .I32 },
    .{ .name = "i64", .kind = .I64 },   .{ .name = "i128", .kind = .I128 },                .{ .name = "u8", .kind = .U8 },
    .{ .name = "u16", .kind = .U16 },   .{ .name = "u32", .kind = .U32 },                  .{ .name = "u64", .kind = .U64 },
    .{ .name = "u128", .kind = .U128 }, .{ .name = "f16", .kind = .F16 },                  .{ .name = "f32", .kind = .F32 },
    .{ .name = "f64", .kind = .F64 },   .{ .name = "f80", .kind = .F80 },                  .{ .name = "f128", .kind = .F128 },
    .{ .name = "type", .kind = .Type }, .{ .name = "comptime_int", .kind = .ComptimeInt }, .{ .name = "comptime_float", .kind = .ComptimeFloat },
};

pub inline fn lookup(type_name: []const u8) ?Type {
    inline for (entries) |entry| {
        if (std.mem.eql(u8, type_name, entry.name)) return entry.kind;
    }
    return null;
}

pub fn isPrimitiveType(type_name: []const u8) bool {
    return lookup(type_name) != null;
}
