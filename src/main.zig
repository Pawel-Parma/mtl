const std = @import("std");
const build = @import("builtin");

const Args = @import("args.zig");
const Printer = @import("printer.zig");
const File = @import("file.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
// const Semantic = @import("semantic.zig");

pub fn main() u8 {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    const printer = Printer.init(stdout);
    defer printer.flush();

    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer switch (debug_allocator.deinit()) {
        .leak => @panic("Memory leak detected\n"),
        .ok => {},
    };
    const base_allocator = switch (build.mode) {
        .Debug => debug_allocator.allocator(),
        else => std.heap.page_allocator,
    };
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const args = Args.init(base_allocator, printer) catch {
        printer.eprint("could not allocate program arguments\n", .{});
        return 1;
    };
    defer args.deinit();
    const exit = args.process();
    if (exit) {
        return 0;
    }

    // TODO: multifile
    const file_path = args.getMainFilePath() orelse {
        printer.eprint("did not provide a file path\n", .{});
        args.printUsage();
        return 0;
    };
    var file = File.init(arena_allocator, printer, file_path) catch |err| {
        printer.print("Error: {any}, failed to read file: {s}\n", .{ err, file_path });
        return 2;
    };

    var tokenizer = Tokenizer.init(arena_allocator, printer, &file);
    tokenizer.tokenize() catch |err| switch (err) {
        error.OutOfMemory => {
            printer.eprint("tokenization failed, OutOfMemory\n", .{});
            return 3;
        },
        else => return 0,
    };

    var parser = Parser.init(arena_allocator, printer, &file);
    parser.parse() catch |err| switch (err) {
        error.OutOfMemory => {
            printer.eprint("parsing failed, OutOfMemory\n", .{});
            return 4;
        },
        else => return 0,
    };

    // var semantic = Semantic.init(arena_allocator, printer, &file);
    // semantic.analyze() catch |err| switch (err) {
    //     error.OutOfMemory => {
    //         printer.eprint("semantic analusis failed, OutOfMemory\n", .{});
    //         return 5;
    //     },
    //     else => return 0,
    // };
    return 0;
}
