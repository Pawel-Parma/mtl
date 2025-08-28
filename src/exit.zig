const std = @import("std");

pub fn panic(code: u8) noreturn {
    std.debug.print("Exiting with code {d}\n", .{code});
    @panic("Exiting");
}

pub fn normal(code: u8) noreturn {
    std.process.exit(code);
}
