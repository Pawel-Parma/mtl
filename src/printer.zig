const std = @import("std");

const File = @import("file.zig");

const Printer = @This();
writer: *std.Io.Writer,
ansi: Ansi,

pub const Ansi = struct {
    writer: *std.Io.Writer,

    pub const Code = enum {
        Reset,
        Bold,

        Black,
        Red,
        Green,
        Yellow,
        Blue,
        Magenta,
        Cyan,
        White,

        BrightBlack,
        BrightRed,
        BrightGreen,
        BrightYellow,
        BrightBlue,
        BrightMagenta,
        BrightCyan,
        BrightWhite,

        pub fn code(self: Code) []const u8 {
            return switch (self) {
                .Reset => "\x1b[0m",
                .Bold => "\x1b[1m",

                .Black => "\x1b[30m",
                .Red => "\x1b[31m",
                .Green => "\x1b[32m",
                .Yellow => "\x1b[33m",
                .Blue => "\x1b[34m",
                .Magenta => "\x1b[35m",
                .Cyan => "\x1b[36m",
                .White => "\x1b[37m",

                .BrightBlack => "\x1b[90m",
                .BrightRed => "\x1b[91m",
                .BrightGreen => "\x1b[92m",
                .BrightYellow => "\x1b[93m",
                .BrightBlue => "\x1b[94m",
                .BrightMagenta => "\x1b[95m",
                .BrightCyan => "\x1b[96m",
                .BrightWhite => "\x1b[97m",
            };
        }
    };

    pub fn init(writer: *std.Io.Writer) Ansi {
        return .{
            .writer = writer,
        };
    }
};

pub fn init(writer: *std.Io.Writer) Printer {
    return .{
        .writer = writer,
        .ansi = .init(writer),
    };
}

pub fn flush(self: *const Printer) void {
    self.writer.flush() catch @panic("Could not flush");
}

pub fn print(self: *const Printer, comptime fmt: []const u8, args: anytype) void {
    self.writer.print(fmt, args) catch @panic("printing failed\n");
}

pub fn printString(self: *const Printer, comptime string: []const u8) void {
    self.print(string, .{});
}

pub fn applyCode(self: *const Printer, code: Ansi.Code) void {
    self.print("{s}", .{code.code()});
}

pub fn printWith(self: *const Printer, codes: anytype, comptime fmt: []const u8, args: anytype) void {
    inline for (codes) |code| {
        self.applyCode(code);
    }
    self.print(fmt, args);
    self.applyCode(.Reset);
}

pub fn printColor(self: *const Printer, code: Ansi.Code, comptime fmt: []const u8, args: anytype) void {
    self.printWith(.{code}, fmt, args);
}

pub fn printError(self: *const Printer, comptime fmt: []const u8, args: anytype) void {
    self.printWith(.{ .Bold, .Red }, "error: ", .{});
    self.print(fmt, args);
}

pub fn pad(self: *const Printer, count: usize) void {
    for (0..count) |_| {
        self.printString(" ");
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
    self.applyCode(.Bold);
    self.print("{s}:{d}:{d} ", .{ file.path, line_number, column });
    self.applyCode(.Red);
    self.print("error: ", .{});
    self.applyCode(.Reset);
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
