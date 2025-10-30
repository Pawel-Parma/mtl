const std = @import("std");

const File = @import("file.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");

const Declaration = @This();
kind: Kind,
symbol_type: Type,
node_index: ?u32,

pub const Kind = enum {
    PubConst,
    PubVar,
    PubFn,
    Const,
    Var,
    Fn,
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

    pub const primitives: std.StaticStringMap(Type) = .initComptime([_]struct { []const u8, Type }{
        .{ "i8", .I8 },                    .{ "i16", .I16 },                      .{ "i32", .I32 },   .{ "i64", .I64 },   .{ "i128", .I128 },
        .{ "u8", .U8 },                    .{ "u16", .U16 },                      .{ "u32", .U32 },   .{ "u64", .U64 },   .{ "u128", .U128 },
        .{ "f16", .F16 },                  .{ "f32", .F32 },                      .{ "f64", .F64 },   .{ "f80", .F80 },   .{ "f128", .F128 },
        .{ "comptime_int", .ComptimeInt }, .{ "comptime_float", .ComptimeFloat }, .{ "bool", .Bool }, .{ "void", .Void }, .{ "type", .Type },
    });

    pub inline fn lookup(type_name: []const u8) ?Type {
        return primitives.get(type_name);
    }

    pub inline fn isPrimitive(type_name: []const u8) bool {
        return lookup(type_name) != null;
    }

    pub fn allowsOperation(self: Type, operation: Node.Kind) bool {
        return switch (operation) {
            .UnaryMinus, .BinaryPlus, .BinaryMinus, .BinaryStar, .BinarySlash => switch (self) {
                .I8, .I16, .I32, .I64, .I128, .U8, .U16, .U32, .U64, .U128, .F16, .F32, .F64, .F80, .F128, .ComptimeInt, .ComptimeFloat => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn equals(left: Type, right: Type) bool {
        return left.canCastTo(right) or right.canCastTo(left);
    }

    pub fn canCastTo(self: Type, to: Type) bool {
        // TODO: add check if the number can fit inside the type
        // TODO: add function and structs
        return switch (self) {
            .ComptimeInt => to.isInt() or to.isFloat(),
            .ComptimeFloat => to.isFloat(),
            else => self == to,
        };
    }

    fn isInt(self: Type) bool {
        return switch (self) {
            .ComptimeInt, .I8, .I16, .I32, .I64, .I128, .U8, .U16, .U32, .U64, .U128 => true,
            else => false,
        };
    }

    fn isFloat(self: Type) bool {
        return switch (self) {
            .ComptimeFloat, .F16, .F32, .F64, .F80, .F128 => true,
            else => false,
        };
    }
};

pub inline fn node(self: *const Declaration, file: *File) ?Node {
    const node_index = self.node_index orelse return null;
    return file.ast.items[node_index];
}
