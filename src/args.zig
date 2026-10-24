const std = @import("std");

const Printer = @import("printer.zig");
const Options = @import("options.zig");

const Args = @This();
allocator: std.mem.Allocator,
printer: Printer,
options: *Options,
args: [][:0]u8,
args_map: std.StringHashMap(?[]const u8),

pub fn init(allocator: std.mem.Allocator, printer: Printer, options: *Options) !Args {
    const args = try std.process.argsAlloc(allocator);
    return .{
        .allocator = allocator,
        .printer = printer,
        .options = options,
        .args = args,
        .args_map = try createArgsMap(allocator, args),
    };
}

pub fn deinit(self: *Args) void {
    std.process.argsFree(self.allocator, self.args);
    self.args_map.deinit();
}

fn contains(self: *const Args, comptime string: []const u8) bool {
    return self.args_map.contains(string);
}

pub fn process(self: *const Args) bool {
    if (self.args.len == 1 or self.contains("--help") or self.contains("-h")) {
        self.printUsage();
        return true;
    }
    if (self.contains("--version") or self.contains("-v")) {
        self.printVersion();
        return true;
    }
    if (self.contains("--debug") or self.contains("-d")) {
        self.options.debug = true;
    }
    return false;
}

pub fn getMainFilePath(self: *const Args) ?[]const u8 {
    for (self.args[1..]) |arg| {
        if (arg.len != 0 and arg[0] != '-') {
            return arg[0..];
        }
    }
    return null;
}

pub fn printUsage(self: *const Args) void {
    self.printer.print(
        \\Usage: mtl [options] <file_path>
        \\Options:
        \\  -h, --help          Show help message
        \\  -v, --version       Print version
        \\  -d, --debug         Enable debug mode
        \\
    , .{});
}

fn printVersion(self: *const Args) void {
    self.printer.print("0.0.0\n", .{});
}

fn createArgsMap(allocator: std.mem.Allocator, args: [][:0]u8) !std.StringHashMap(?[]const u8) {
    var map = std.StringHashMap(?[]const u8).init(allocator);
    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |i| {
            try map.put(arg[0..i], arg[(i + 1)..]);
        } else {
            try map.put(arg, null);
        }
    }
    return map;
}
