const std = @import("std");

const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
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

    const file = std.fs.cwd().openFile(args[1], .{}) catch {
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

    _ = file.readAll(buffer) catch {
        std.debug.print("Failed to read file\n", .{});
        exit(7);
    };

    var tokenizer = Tokenizer.init(allocator, buffer);
    defer tokenizer.deinit();
    tokenizer.tokenize() catch {
        std.debug.print("Tokenization failed\n", .{});
        exit(8);
    };

    var parser = Parser.init(allocator, tokenizer.tokens.items, buffer);
    defer parser.deinit() catch {
        std.debug.print("Parser deinitialization failed LOL\n", .{});
        exit(9);
    };
    parser.parse() catch {
        std.debug.print("Parsing failed\n", .{});
        exit(10);
    };
}


