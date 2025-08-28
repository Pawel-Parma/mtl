const std = @import("std");

const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const exit = @import("exit.zig");

pub fn main() void {
    const allocator = std.heap.page_allocator;

    const args = std.process.argsAlloc(allocator) catch {
        std.debug.print("Failed to allocate memory for program arguments\n", .{});
        exit.normal(1);
    };
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) {
        printUsage();
        return;
    } else if (args.len > 3) {
        std.debug.print("Too many program arguments provided, see usage using: mtl --help\n", .{});
        exit.normal(2);
    }

    // TODO: make program args handling better as currently args are positional
    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        printUsage();
    }

    const file_path = args[1];
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        std.debug.print("Failed to open file: {s}\n", .{file_path});
        exit.normal(3);
    };
    defer file.close();

    const file_size = file.getEndPos() catch {
        std.debug.print("Failed to get file size: {s}\n", .{file_path});
        exit.normal(4);
    };

    const buffer = allocator.alloc(u8, file_size) catch {
        std.debug.print("Failed to allocate buffer for file: {s}\n", .{file_path});
        exit.normal(5);
    };
    defer allocator.free(buffer);

    _ = file.readAll(buffer) catch {
        std.debug.print("Failed to read file: {s}\n", .{file_path});
        exit.normal(6);
    };

    var tokenizer = Tokenizer.init(allocator, buffer);
    defer tokenizer.deinit();
    tokenizer.tokenize() catch |err| {
        std.debug.print("Tokenization failed: {any}\n", .{err});
        exit.normal(7);
    };
    const tokens = tokenizer.tokens.items;
    std.debug.print("Tokens:\n", .{});
    for (tokens) |token| {
        const token_text = buffer[token.start..token.end];
        std.debug.print("  {any} (start={any}, end={any}): \"{s}\"\n", .{ token.kind, token.start, token.end, token_text });
    }

    var parser = Parser.init(allocator, tokens, buffer);
    defer parser.deinit() catch |err| {
        std.debug.print("Parser deinitialization failed, LOL: {any}\n", .{err});
        exit.normal(8);
    };
    parser.parse() catch |err| {
        std.debug.print("Parsing failed: {any}\n", .{err});
        exit.normal(9);
    };
    const ast = parser.ast;

    std.debug.print("\nAST:\n", .{});
    for (ast.items) |node| {
        printNode(node, 0, tokens, buffer);
    }
}

fn printUsage() void {
    std.debug.print("Usage: mtl [options] <file>\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --help, -h       Show this help message\n", .{});
}

const Node = @import("parser.zig").Node;
const Token = @import("tokenizer.zig").Token;

fn printNode(node: Node, depth: usize, tokens: []const Token, buffer: []const u8) void {
    var indent_buf: [32]u8 = undefined; // adjust size as needed
    const indent = indent_buf[0..@min(depth * 2, indent_buf.len)];
    for (indent) |*c| {
        c.* = ' ';
    }
    if (node.token_index) |token_index| {
        const token = tokens[token_index];
        const token_text = buffer[token.start..token.end];
        std.debug.print("{s}{any} (token_index={any}) (token_kind={any}) (token_text=\"{s}\")\n", .{ indent, node.kind, token_index, token.kind, token_text });
    } else {
        std.debug.print("{s}{any} (token_index=null)\n", .{ indent, node.kind });
    }
    for (node.children.items) |child| {
        printNode(child, depth + 1, tokens, buffer);
    }
}
