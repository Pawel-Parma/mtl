const std = @import("std");

const Token = @import("token.zig");
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
    self.writer.print(fmt, args) catch @panic("Could not print failed\n");
}

pub fn dprint(self: *const Printer, comptime fmt: []const u8, args: anytype) void {
    self.print(fmt, args);
    self.flush();
}

pub fn dprintanyn(self: *const Printer, any: anytype) void {
    self.print("{any}\n", .{any});
    self.flush();
}

pub fn printString(self: *const Printer, string: []const u8) void {
    self.print("{s}", .{string});
}

pub fn applyCode(self: *const Printer, code: Ansi.Code) void {
    self.print("{s}", .{code.code()});
}

pub fn printColor(self: *const Printer, comptime fmt: []const u8, args: anytype) void {
    self.print(resolveColorFmt(fmt), args);
}

pub fn printCode(self: *const Printer, code: Ansi.Code, comptime fmt: []const u8, args: anytype) void {
    self.applyCode(code);
    self.print(fmt, args);
    self.applyCode(.Reset);
}

pub fn printError(self: *const Printer, comptime fmt: []const u8, args: anytype) void {
    self.applyCode(.Bold);
    self.applyCode(.Red);
    self.printString("error: ");
    self.applyCode(.Reset);
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
    token: Token,
) void {
    const line_info = file.lineInfo(token);
    const column = token.start - line_info.start;
    const line = File.getLine(file.buffer, line_info.start, token.start, @intCast(file.buffer.len));
    self.applyCode(.Bold);
    self.print("{s}:{d}:{d} ", .{ file.path, line_info.number, column });
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
    while (j < token.len() and column + j < line.len and line[column + j] != '\n') : (j += 1) {
        self.print("~", .{});
    }
    self.print("\n", .{});
}

fn resolveColorFmt(comptime fmt: []const u8) []const u8 {
    const fields = @typeInfo(Ansi.Code).@"enum".fields;
    const open_char = '<';
    const close_char = '>';
    const sep_char = ':';

    comptime var out: []const u8 = "";
    comptime var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != open_char) {
            out = out ++ fmt[i .. i + 1];
            continue;
        }
        const end_idx = std.mem.indexOfScalarPos(u8, fmt, i + 1, close_char) orelse {
            out = out ++ fmt[i .. i + 1];
            continue;
        };
        const inner = fmt[i + 1 .. end_idx];
        if (std.mem.indexOfScalar(u8, inner, sep_char)) |colon_idx| {
            const color_name = inner[0..colon_idx];
            const rest = inner[colon_idx + 1 ..];
            const color_opt = lookupAnsiCode(color_name, fields);
            if (color_opt) |color| {
                const inner_resolved = resolveColorFmt(rest);
                out = out ++ color.code() ++ inner_resolved ++ Ansi.Code.Reset.code();
                i = end_idx;
                continue;
            }
        } else {
            const code_opt = lookupAnsiCode(inner, fields);
            if (code_opt) |code| {
                out = out ++ code.code();
                i = end_idx;
                continue;
            }
        }
        out = out ++ fmt[i .. i + 1];
    }
    return out;
}

fn lookupAnsiCode(name: []const u8, fields: anytype) ?Ansi.Code {
    inline for (fields) |f| {
        if (std.mem.eql(u8, f.name, name))
            return @field(Ansi.Code, f.name);
    }
    return null;
}
