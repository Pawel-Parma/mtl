const std = @import("std");
const builtin = @import("builtin");

pub fn panic(code: u8) noreturn {
    std.debug.print("Exiting with code {d}\n", .{code});
    @panic("Exiting");
}

pub fn exit(code: u8) noreturn {
    std.process.exit(code);
}


pub inline fn dprint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}

pub inline fn rprint(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}