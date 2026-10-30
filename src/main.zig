const std = @import("std");
const build = @import("builtin");

const Printer = @import("printer.zig");
const Args = @import("args.zig");
const File = @import("file.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");

const Code = struct {
    const Success: u8 = 0;
    const AllocatingArgsFailed: u8 = 1;
    const NoFilePathProvided: u8 = 2;
    const ReadingFileFailed: u8 = 3;
    const TokenizationFailed: u8 = 4;
    const ParsingFailed: u8 = 5;
    const SemanticAnalysisFailed: u8 = 6;
};

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    const allocator = init.gpa;
    var arena = init.arena;
    const arena_allocator = arena.allocator();

    var buffer: [2048]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &buffer);
    const printer = Printer.init(io, &stdout_file_writer);
    defer printer.flush();

    var args = Args.init(allocator, printer, init.minimal.args) catch |err| {
        printer.printError("failed to allocate program arguments: {any}\n", .{err});
        return Code.AllocatingArgsFailed;
    };
    defer args.deinit();
    if (args.process()) {
        return Code.Success;
    }

    const file_path = args.getMainFilePath() orelse {
        printer.printError("Did not provide a file path\n", .{});
        args.printUsage();
        return Code.NoFilePathProvided;
    };
    var file = File.init(io, arena_allocator, printer, &args.options, file_path) catch |err| {
        printer.printError("Failed to read file: {any}\n", .{err});
        return Code.ReadingFileFailed;
    };

    var tokenizer = Tokenizer.init(arena_allocator, &file);
    tokenizer.tokenize() catch {
        printer.printError("Tokenization failed\n", .{});
        return Code.TokenizationFailed;
    };

    var parser = Parser.init(arena_allocator, printer, &file);
    parser.parse() catch {
        printer.printError("Parsing failed\n", .{});
        return Code.ParsingFailed;
    };

    var semantic = Semantic.init(arena_allocator, printer, &file);
    semantic.analyze() catch {
        printer.printError("Semantic analysis failed\n", .{});
        return Code.SemanticAnalysisFailed;
    };

    return Code.Success;
}
