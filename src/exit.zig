const std = @import("std");

pub fn exit(code: u8) noreturn {
    std.debug.print("Exiting with code {d}\n", .{code});
    @panic("Exiting");
}
