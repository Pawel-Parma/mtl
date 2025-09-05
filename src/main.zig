const std = @import("std");
const core = @import("core.zig");

const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");

pub fn main() !u8 {
    const allocator = std.heap.page_allocator;

    const args = std.process.argsAlloc(allocator) catch {
        core.rprint("Failed to allocate memory for program arguments\n", .{});
        core.exit(1);
    };
    defer std.process.argsFree(allocator, args);
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
    const file_buffer = core.readFileToBuffer(allocator, file_path) catch |err| {
        core.rprint("Failed to read file: {s} - error: {any}\n", .{ file_path, err });
        core.exit(3);
    };
    defer allocator.free(file_buffer);

    var tokenizer = Tokenizer.init(allocator, file_buffer, file_path);
    defer tokenizer.deinit();
    tokenizer.tokenize() catch |err| switch (err) {
        error.OutOfMemory => core.exitCode("Tokenization failed", .OutOfMemory),
        error.TokenizeFailed => return 0,
    };
    const tokens = tokenizer.tokens.items;

    var parser = Parser.init(allocator, file_buffer, file_path, tokens);
    defer parser.deinit() catch core.exitCode("Parser deinitialization failed", .OutOfMemory);
    parser.parse() catch |err| switch (err) {
        error.OutOfMemory => core.exitCode("Parsing failed", .OutOfMemory),
        error.UnexpectedToken => return 0,
    };
    const ast = parser.ast;

    var semantic = Semantic.init(allocator, file_buffer, tokens, ast);
    defer semantic.deinit();
    semantic.analyze() catch |err| {
        core.rprint("Semantic analysis failed: {any}\n", .{err});
        core.exit(10);
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
