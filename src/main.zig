const std = @import("std");
const build = @import("builtin");
const core = @import("core.zig");

const Args = @import("args.zig");
const File = @import("file.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");

pub fn main() !u8 {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer switch (debug_allocator.deinit()) {
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

    const args = Args.init(base_allocator) catch {
        core.rprint("Error: could not allocate program arguments\n", .{});
        core.exit(1);
    };
    args.process();

    // TODO: multifile
    const file_path = args.getMainFilePath() orelse {
        core.rprint("Error: did not provide a file path\n", .{});
        Args.printUsage();
        core.exit(2);
    };
    var file = File.init(arena_allocator, file_path) catch |err| {
        core.rprint("Error: {any}, failed to read file: {s}\n", .{ err, file_path });
        core.exit(3);
    };

    var tokenizer = Tokenizer.init(arena_allocator, &file);
    tokenizer.tokenize() catch |err| switch (err) {
        error.OutOfMemory => {
            core.rprint("Error: tokenization failed, OutOfMemory", .{});
            core.exit(4);
        },
        else => return 0,
    };

    var parser = Parser.init(arena_allocator, &file);
    parser.parse() catch |err| switch (err) {
        error.OutOfMemory => {
            core.rprint("Error: parsing failed, OutOfMemory", .{});
            core.exit(4);
        },
        else => return 0,
    };

    var semantic = Semantic.init(arena_allocator, &file);
    semantic.analyze() catch |err| switch (err) {
        error.OutOfMemory => {
            core.rprint("Error: semantic analusis failed, OutOfMemory", .{});
            core.exit(4);
        },
        else => return 0,
    };
    return 0;
}
