const std = @import("std");
const builtin = @import("builtin");

const File = @import("file.zig");

const Printer = @This();
writer: *std.Io.Writer,
ansi: Ansi,

const Ansi = struct {
    writer: *std.Io.Writer,

    const Style = enum {
        Red,
        Bold,
        Reset,

        fn code(style: Style) []const u8 {
            return switch (style) {
                .Red => "\x1b[31m",
                .Bold => "\x1b[1m",
                .Reset => "\x1b[0m",
            };
        }
    };

    pub fn init(writer: *std.Io.Writer) Ansi {
        return .{
            .writer = writer,
        };
    }

    pub fn apply(self: *Ansi, style: Style) void {
        self.writer.print("{s}", .{style.code()}) catch @panic("printing failed\n");
    }
};

pub fn init(writer: *std.Io.Writer) Printer {
    return .{
        .writer = writer,
        .ansi = .init(writer),
    };
}

pub fn print(self: *const Printer, comptime fmt: []const u8, args: anytype) void {
    self.writer.print(fmt, args) catch @panic("prining failed\n");
}

pub fn dprint(self: *Printer, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        self.print(fmt, args);
    }
}

pub fn printSourceLine(
    self: *Printer,
    comptime fmt: []const u8,
    args: anytype,
    file: *File,
    line_number: usize,
    column: usize,
    line: []const u8,
    token_length: usize,
) void {
    self.ansi.apply(.Bold);
    self.print("{s}:{d}:{d} ", .{ file.path, line_number, column });
    self.ansi.apply(.Red);
    self.print("error: ", .{});
    self.ansi.apply(.Reset);
    self.print(fmt, args);
    self.print("    {s}\n", .{line});
    self.print("    ", .{});
    var i: usize = 0;
    while (i < column) : (i += 1) {
        self.print(" ", .{});
    }
    self.print("^", .{});
    var j: usize = 1;
    while (j < token_length and column + j < line.len and line[column + j] != '\n') : (j += 1) {
        self.print("~", .{});
    }
    self.print("\n", .{});
}
