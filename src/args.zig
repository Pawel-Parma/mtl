const std = @import("std");
const exit = std.process.exit;

const Printer = @import("printer.zig");
const options = @import("options.zig");

const Args = @This();
allocator: std.mem.Allocator,
printer: Printer,
args: [][:0]u8,
args_map: std.StringHashMap(?[]const u8),

pub fn init(allocator: std.mem.Allocator, printer: Printer) !Args {
    const args = try std.process.argsAlloc(allocator);
    const argsMap = try createArgsMap(allocator, args);
    return .{
        .allocator = allocator,
        .printer = printer,
        .args = args,
        .args_map = argsMap,
    };
}

pub fn deinit(self: *const Args) void {
    std.process.argsFree(self.allocator, self.args);
}

pub fn conatins(self: *const Args, comptime string: []const u8) bool {
    return self.args_map.contains(string);
}

pub fn process(self: *const Args) bool {
    if (self.args.len == 1 or self.conatins("--help") or self.conatins("-h")) {
        self.printUsage();
        return true;
    }
    if (self.conatins("--version") or self.conatins("-v")) {
        self.printVersion();
        return true;
    }
    if (self.conatins("--debug") or self.conatins("-d")) {
        options.debug = true;
    }
    return false;
}

pub fn getMainFilePath(self: *const Args) ?[]const u8 {
    for (self.args[1..]) |arg| {
        if (arg.len == 0 or arg[0] == '-') {
            continue;
        }
        return arg[0..];
    }
    return null;
}

pub fn printUsage(self: *const Args) void {
    self.printer.print(
        \\Usage: mtl [options] <file_path>
        \\Options:
        \\  --help, -h          Print help message
        \\  --version, -v       Print version 
        \\  --debug, -d         Enable debug mode
        \\
    , .{});
}

pub fn printVersion(self: *const Args) void {
    self.printer.print("0.0.0\n", .{});
}

fn createArgsMap(allocator: std.mem.Allocator, args: [][:0]u8) !std.StringHashMap(?[]const u8) {
    var args_map: std.StringHashMap(?[]const u8) = .init(allocator);
    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq_index| {
            const key = arg[0..eq_index];
            const value = arg[(eq_index + 1)..];
            try args_map.put(key, value);
        } else {
            try args_map.put(arg, null);
        }
    }
    return args_map;
}
