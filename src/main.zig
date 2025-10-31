const std = @import("std");
const build = @import("builtin");

const Args = @import("args.zig");
const Printer = @import("printer.zig");
const File = @import("file.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");

pub fn main() u8 {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    const printer = Printer.init(stdout);

    const allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const args = Args.init(allocator, printer) catch {
        printer.printError("could not allocate program arguments\n", .{});
        return 1;
    };
    defer args.deinit();
    const exit = args.process();
    if (exit) {
        return 0;
    }

    // TODO: multifile
    const file_path = args.getMainFilePath() orelse {
        printer.printError("did not provide a file path\n", .{});
        args.printUsage();
        return 0;
    };
    var file = File.init(arena_allocator, printer, file_path) catch |err| {
        printer.printError("{any}, failed to read file: {s}\n", .{ err, file_path });
        return 2;
    };

    var tokenizer = Tokenizer.init(arena_allocator, printer, &file);
    tokenizer.tokenize() catch |err| switch (err) {
        error.OutOfMemory => {
            printer.printError("tokenization failed, OutOfMemory\n", .{});
            return 3;
        },
        else => return 0,
    };

    var parser = Parser.init(arena_allocator, printer, &file);
    parser.parse() catch |err| switch (err) {
        error.OutOfMemory => {
            printer.printError("parsing failed, OutOfMemory\n", .{});
            return 4;
        },
        else => return 0,
    };

    var semantic = Semantic.init(arena_allocator, printer, &file);
    semantic.analyze() catch |err| switch (err) {
        error.OutOfMemory => {
            printer.printError("semantic analusis failed, OutOfMemory\n", .{});
            return 5;
        },
        else => return 0,
    };
    return 0;
}
