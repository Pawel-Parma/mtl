const std = @import("std");
const core = @import("core.zig");

const Args = @This();
allocator: std.mem.Allocator,
args: [][:0]u8,

pub fn init(allocator: std.mem.Allocator) !Args {
    const args = try std.process.argsAlloc(allocator);
    core.dprint("{any}\n", .{args});
    // TODO: is the first arg the prog path?
    return .{
        .allocator = allocator,
        .args = args,
    };
}

pub fn deinit(self: *Args) void {
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

pub fn process(self: *const Args) void {
    if (self.args.len < 2) {
        printUsage();
        core.exit(0);
    }
    if (self.conatins("--help") or self.conatins("-h")) {
        printUsage();
        core.exit(0);
    }
    if (self.conatins("--version") or self.conatins("-v")) {
        core.rprint("0.0.0", .{});
        core.exit(0);
    }
}

pub fn getMainFilePath(self: *const Args) ?[]const u8 {
    for (self.args) |arg| {
        if (arg.len == 0 or arg[0] == 'h') {
            continue;
        }
        return arg[0..];
    }
    return null;
}

pub fn printUsage() void {
    core.rprint(
        \\Usage: mtl [options] <file>
        \\Options:
        \\  --help, -h       Show this help message
        \\
    , .{});
}
