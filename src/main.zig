const std = @import("std");
const Tokenizer = @import("tokenizer.zig");
const exit = @import("exit.zig").exit;


pub fn main() void {
    const allocator = std.heap.page_allocator;

    const args = std.process.argsAlloc(allocator) catch {
        std.debug.print("Failed to allocate args\n", .{});
        exit(1);
    };
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) {
        std.debug.print("No Args Provided\n", .{});
        exit(2);
    } else if (args.len > 3) {
        std.debug.print("Too Many Args Provided\n", .{});
        exit(3);
    }

    const relative_path = args[1];
    std.debug.print("{s}\n", .{relative_path});

    const file = std.fs.cwd().openFile(relative_path, .{}) catch {
        std.debug.print("Failed to open file\n", .{});
        exit(4);
    };
    defer file.close();

    const file_size = file.getEndPos() catch {
        std.debug.print("Failed to get file size\n", .{});
        exit(5);
    };

    const buffer = allocator.alloc(u8, file_size) catch {
        std.debug.print("Failed to allocate buffer\n", .{});
        exit(6);
    };
    defer allocator.free(buffer);

    const file_len = file.readAll(buffer) catch {
        std.debug.print("Failed to read file\n", .{});
        exit(7);
    };

    std.debug.print("File {d} contents:\n{s} \n", .{ file_len, buffer });

    // Tokenize the file contents
    var tokenizer = Tokenizer.init(allocator, buffer);
    tokenizer.tokenize() catch {
        std.debug.print("Tokenization failed\n", .{});
        exit(8);
    };
    const tokens = tokenizer.tokens;
    std.debug.print("Tokens: {d}\n", .{tokens.items.len});

    // print tokens
    for (tokens.items) |token| {
        std.debug.print("Token: {d} - {d} - {d} - {s}\n", .{token.kind, token.position_start, token.position_end, buffer[token.position_start..token.position_end]});
    }
}


