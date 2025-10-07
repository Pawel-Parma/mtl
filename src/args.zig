const std = @import("std");
const exit = std.process.exit;

const Printer = @import("printer.zig");

const Args = @This();
allocator: std.mem.Allocator,
printer: Printer,
args: [][:0]u8,

pub fn init(allocator: std.mem.Allocator, printer: Printer) !Args {
    const args = try std.process.argsAlloc(allocator);
    return .{
        .allocator = allocator,
        .printer = printer,
        .args = args,
    };
}

pub fn deinit(self: *const Args) void {
    std.process.argsFree(self.allocator, self.args);
}

pub fn conatins(self: *const Args, comptime string: []const u8) bool {
    for (self.args) |arg| {
        if (std.mem.eql(u8, arg, string)) {
            return true;
        }
    }
    return false;
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
        \\Usage: mtl [options] <file>
        \\Options:
        \\  --help, -h          Show help message
        \\  --version, -v       Show version 
        \\
    , .{});
}
pub fn printVersion(self: *const Args) void {
    self.printer.print("0.0.0\n", .{});
}
