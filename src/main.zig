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
    defer printer.flush();

    const allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const args = Args.init(allocator, printer) catch |err| {
        printer.printError("Failed to allocate program arguments: {any}\n", .{err});
        return Code.AllocatingArgsFailed;
    };
    defer args.deinit();
    if (args.process()) {
        return Code.Success;
    }

    // TODO: multifile
    const file_path = args.getMainFilePath() orelse {
        printer.printError("Did not provide a file path\n", .{});
        args.printUsage();
        return Code.NoFilePathProvided;
    };
    var file = File.init(arena_allocator, printer, file_path) catch |err| {
        printer.printError("Failed to read file: {any}\n", .{err});
        return Code.ReadingFileFailed;
    };

    var tokenizer = Tokenizer.init(arena_allocator, printer, &file);
    tokenizer.tokenize() catch |err| {
        printer.printError("Tokenization failed: {any}\n", .{err});
        return Code.TokenizationFailed;
    };

    var parser = Parser.init(arena_allocator, printer, &file);
    parser.parse() catch |err| {
        printer.printError("Parsing failed: {any}\n", .{err});
        return Code.ParsingFailed;
    };

    var semantic = Semantic.init(arena_allocator, printer, &file);
    semantic.analyze() catch |err| {
        printer.printError("Semantic analysis failed: {any}\n", .{err});
        return Code.SemanticAnalysisFailed;
    };

    return Code.Success;
}

const Code = struct {
    const Success: u8 = 0;
    const AllocatingArgsFailed: u8 = 1;
    const NoFilePathProvided: u8 = 2;
    const ReadingFileFailed: u8 = 3;
    const TokenizationFailed: u8 = 4;
    const ParsingFailed: u8 = 5;
    const SemanticAnalysisFailed: u8 = 6;
};
