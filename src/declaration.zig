const std = @import("std");
const Token = @import("token.zig");
const Node = @import("node.zig");

kind: Kind,
symbol_type: Type,
expr: ?Node,

pub const Kind = enum {
    Var,
    Const,
    Function,
};

pub const Type = enum {
    I8,
    I16,
    I32,
    I64,
    I128,

    U8,
    U16,
    U32,
    U64,
    U128,

    F16,
    F32,
    F64,
    F80,
    F128,

    ComptimeInt,
    ComptimeFloat,

    Bool,

    Void,

    Type,

    Function,

    pub inline fn toInt(self: Type) u8 {
        return @intFromEnum(self);
    }

    pub fn equals(left: Type, right: Type) bool {
        if (left == .ComptimeInt or left == .ComptimeFloat or right == .ComptimeInt or right == .ComptimeFloat) {
            return left.leftCastOnlyEquals(right) or right.leftCastOnlyEquals(left);
        }
        return left.toInt() == right.toInt();
    }

    pub fn leftCastOnlyEquals(left: Type, right: Type) bool {
        if (left == .ComptimeInt or left == .ComptimeFloat) {
            // TODO: add check if the number can fit inside the type
            switch (left) {
                .ComptimeInt => switch (right) {
                    .ComptimeInt, .ComptimeFloat, .I8, .I16, .I32, .I64, .I128, .U8, .U16, .U32, .U64, .U128, .F16, .F32, .F64, .F80, .F128 => return true,
                    else => return false,
                },
                .ComptimeFloat => {
                    switch (right) {
                        .ComptimeFloat, .F16, .F32, .F64, .F80, .F128 => return true,
                        else => return false,
                    }
                },
                else => {},
            }
        }
        return left.toInt() == right.toInt();
    }
    pub fn allowsOperation(self: Type, operation: Node.Kind) bool {
        // TODO: check for user defined types
        return switch (operation) {
            .UnaryMinus, .BinaryPlus, .BinaryMinus, .BinaryStar, .BinarySlash => switch (self) {
                .I8, .I16, .I32, .I64, .I128, .U8, .U16, .U32, .U64, .U128, .F16, .F32, .F64, .F80, .F128, .ComptimeInt, .ComptimeFloat => true,
                else => false,
            },
            else => false,
        };
    }

    pub const entries: std.StaticStringMap(Type) = .initComptime([_]struct { []const u8, Type }{
        .{ "i8", .I8 },                    .{ "i16", .I16 },                      .{ "i32", .I32 },   .{ "i64", .I64 },   .{ "i128", .I128 },
        .{ "u8", .U8 },                    .{ "u16", .U16 },                      .{ "u32", .U32 },   .{ "u64", .U64 },   .{ "u128", .U128 },
        .{ "f16", .F16 },                  .{ "f32", .F32 },                      .{ "f64", .F64 },   .{ "f80", .F80 },   .{ "f128", .F128 },
        .{ "comptime_int", .ComptimeInt }, .{ "comptime_float", .ComptimeFloat }, .{ "bool", .Bool }, .{ "type", .Type }, .{ "void", .Void },
    });
    pub fn lookup(type_name: []const u8) ?Type {
        return entries.get(type_name);
    }

    pub fn isPrimitive(type_name: []const u8) bool {
        return lookup(type_name) != null;
    }
};
