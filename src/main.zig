const std = @import("std");
const core = @import("core.zig");

const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");

pub fn main() u8 {
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

    const file_path = args[1];
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        core.rprint("Failed to open file: {s}\n", .{file_path});
        core.exit(3);
    };
    defer file.close();

    const file_size = file.getEndPos() catch {
        core.rprint("Failed to get file size: {s}\n", .{file_path});
        core.exit(4);
    };

    const buffer = allocator.alloc(u8, file_size) catch {
        core.rprint("Failed to allocate buffer for file: {s}\n", .{file_path});
        core.exit(5);
    };
    defer allocator.free(buffer);

    _ = file.readAll(buffer) catch {
        core.rprint("Failed to read file: {s}\n", .{file_path});
        core.exit(6);
    };

    var tokenizer = Tokenizer.init(allocator, buffer, file_path);
    defer tokenizer.deinit();
    tokenizer.tokenize() catch |err| switch (err) {
        error.TokenizeFailed => return 0,
        error.OutOfMemory => {
            core.rprint("Tokenization failed: {any}\n", .{err});
            core.exit(8);
        },
    };
    const tokens = tokenizer.tokens.items;

    var parser = Parser.init(allocator, buffer, tokens);
    defer parser.deinit() catch |err| {
        core.rprint("Parser deinitialization failed, LOL: {any}\n", .{err});
        core.exit(8);
    };
    parser.parse() catch |err| {
        core.rprint("Parsing failed: {any}\n", .{err});
        core.exit(9);
    };
    const ast = parser.ast;

    var semantic = Semantic.init(allocator, buffer, tokens, ast);
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
