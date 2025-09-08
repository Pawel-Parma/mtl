const std = @import("std");
const build = @import("builtin");
const core = @import("core.zig");

const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");

pub fn main() !u8 {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer switch(debug_allocator.deinit()) {
        .ok => {},
        .leak => core.rprint("Memory leak detected\n", .{}),
    };
    const base_allocator = switch (build.mode) {
        .Debug => debug_allocator.allocator(),
        else => std.heap.page_allocator,
    };
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const args = std.process.argsAlloc(base_allocator) catch {
        core.rprint("Failed to allocate memory for program arguments\n", .{});
        core.exit(1);
    };
    defer std.process.argsFree(base_allocator, args);
    if (args.len < 2) {
        printUsage();
        return 0;
    } else if (args.len > 3) {
        core.rprint("Too many program arguments provided, see usage using: mtl --help\n", .{});
        core.exit(2);
    }
    // TODO: make program args handling better as currently args are positional
    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        printUsage();
    }

    const file_path = args[1]; // TODO: multifile
    const file_buffer = core.readFileToBuffer(arena_allocator, file_path) catch |err| {
        core.rprint("Failed to read file: {s} - error: {any}\n", .{ file_path, err });
        core.exit(3);
    };

    var tokenizer = Tokenizer.init(arena_allocator, file_buffer, file_path);
    tokenizer.tokenize() catch |err| switch (err) {
        error.OutOfMemory => core.exitCode("Tokenization failed", .OutOfMemory),
        else => return 0,
    };
    const tokens = tokenizer.tokens.items;

    var parser = Parser.init(arena_allocator, file_buffer, file_path, tokens);
    parser.parse() catch |err| switch (err) {
        error.OutOfMemory => core.exitCode("Parsing failed", .OutOfMemory),
        else => return 0,
    };
    const ast = parser.ast;

    var semantic = Semantic.init(arena_allocator, file_buffer, tokens, ast);
    semantic.analyze() catch |err| switch(err) {
        error.OutOfMemory => core.exitCode("Semantic analysis failed", .OutOfMemory),
        else => return 0,
    };
    return 0;
}

fn printUsage() void {
    core.rprint(
        \\Usage: mtl [options] <file>
        \\Options:
        \\  --help, -h       Show this help message
    , .{});
}
