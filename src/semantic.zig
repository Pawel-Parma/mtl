const std = @import("std");

const Printer = @import("printer.zig");
const File = @import("file.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");

const Semantic = @This();
allocator: std.mem.Allocator,
printer: Printer,
file: *File,

pub const Error = error{} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, printer: Printer, file: *File) Semantic {
    return .{
        .allocator = allocator,
        .file = file,
        .printer = printer,
    };
}

pub fn analyze(self: *Semantic) !void {
    // TODO: make global scope lazily analyzed
    try self.populateGlobalScope();
    try self.startAnalisisFromMain();
    self.file.printScopes();
}

inline fn advance(self: *Semantic) void {
    self.file.selected += 1;
}

inline fn advanceGetIndex(self: *Semantic) u32 {
    self.file.selected += 1;
    return self.file.selected - 1;
}

fn advanceWithChildren(self: *Semantic) void {
    var to_advance = self.peek().children;
    self.advance();
    while (!self.isAtEnd() and to_advance != 0) {
        to_advance += self.peek().children;
        to_advance -= 1;
        self.advance();
    }
}

inline fn peek(self: *Semantic) Node {
    return self.file.ast.items[self.file.selected];
}

inline fn get(self: *Semantic, node_index: u32) Node {
    return self.file.ast.items[node_index];
}

inline fn isAtEnd(self: *Semantic) bool {
    return self.file.selected >= self.file.ast.items.len;
}

fn getIfInScope(self: *Semantic, identifier: []const u8) ?Declaration {
    if (self.file.global_scope.get(identifier)) |id| {
        return id;
    }
    for (self.file.scopes.items) |*scope| {
        if (scope.get(identifier)) |id| {
            return id;
        }
    }
    return null;
}

inline fn isInScope(self: *Semantic, identifier: []const u8) bool {
    return self.getIfInScope(identifier) != null;
}

fn getCurrentScope(self: *Semantic) *std.StringHashMap(Declaration) {
    if (self.file.scopes.items.len > 0) {
        return &self.file.scopes.items[self.file.scopes.items.len - 1];
    }
    return &self.file.global_scope;
}

fn reportError(self: *Semantic, comptime fmt: []const u8, args: anytype) noreturn {
    self.file.success = false;
    self.printer.print(fmt, args);
    self.printer.flush();
    @panic("ERROR!\n");
}

fn populateGlobalScope(self: *Semantic) Error!void {
    while (!self.isAtEnd()) {
        const node = self.peek();
        switch (node.kind) {
            .Declaration => try self.declarationNode(),
            .Function => try self.functionNode(),
            else => self.reportError("Unexpected node : {any}\n", .{node}),
        }
    }
}

fn declarationNode(self: *Semantic) !void {
    const declaration = self.peek();
    self.advance();

    const identifier_name = self.peek().string(self.file);
    self.advance();
    if (Declaration.Type.isPrimitive(identifier_name)) {
        self.reportError("Cannot declare variable '{s}', shadows primitive type\n", .{identifier_name});
    }
    if (self.isInScope(identifier_name)) {
        self.reportError("Cannot declare variable '{s}', shadows declaration\n", .{identifier_name});
    }

    const type_identifier = self.peek();
    const type_index = self.file.selected;
    self.advance();

    const expression_index = self.file.selected;
    self.advanceWithChildren();

    const expression_type = self.inferType(expression_index);
    const declared_type = if (type_identifier.token_index) |_| self.resolveType(type_index) else expression_type;
    if (!declared_type.equals(expression_type)) {
        self.reportError("Type mismatch in declaration of '{s}', expected {any}, got {any}\n", .{ identifier_name, declared_type, expression_type });
    }

    var current_scope = self.getCurrentScope();
    const kind: Declaration.Kind = if (declaration.token(self.file).?.kind == .Const) .Const else .Var;
    try current_scope.put(identifier_name, .{
        .kind = kind,
        .symbol_type = declared_type,
        .node_index = expression_index,
    });
}

fn inferType(self: *Semantic, node_index: u32) Declaration.Type {
    const node = self.get(node_index);
    switch (node.kind) {
        .IntLiteral => return .ComptimeInt,
        .FloatLiteral => return .ComptimeFloat,
        .UnaryMinus => {
            const child_type = self.inferType(node_index + 1);
            if (!child_type.allowsOperation(.UnaryMinus)) {
                self.reportError("Operation {any} is not allowed on type {any}\n", .{ node.kind, child_type });
            }
            return child_type;
        },
        .BinaryPlus, .BinaryMinus, .BinaryStar, .BinarySlash => {
            const left_type = self.inferType(node_index + 1);
            const right_type = self.inferType(node_index + 2);
            if (left_type.equals(right_type)) {
                if (!left_type.allowsOperation(node.kind)) {
                    self.reportError("Operation {any} is not allowed on type {any}\n", .{ node.kind, left_type });
                }
                if (!right_type.allowsOperation(node.kind)) {
                    self.reportError("Operation {any} is not allowed on type {any}\n", .{ node.kind, right_type });
                }
                return left_type;
            }
            self.reportError("Type mismatch in binary operator, expected {any}, got {any}\n", .{ left_type, right_type });
        },
        .Identifier => {
            // TODO: Here lazy analisis
            const node_name = node.string(self.file);
            if (Declaration.Type.isPrimitive(node_name)) {
                return .Type;
            }
            if (self.getIfInScope(node_name)) |declaration| {
                return declaration.symbol_type;
            }
            self.reportError("Undefined identifier '{s}'\n", .{node_name});
        },
        .Expression => {
            const first_expr_type = self.inferType(node_index + 1);
            // for (node.children) |expr| {
            //     const expr_type = self.inferType(expr);
            //     if (!first_expr_type.equals(expr_type)) {
            //         self.reportError("Type mismatch in expression, expected {any}, got {any}", .{ first_expr_type, expr_type });
            //     }
            // }
            return first_expr_type;
        },
        //         .Call => {
        //             const function_node = self.callNode(node);
        //             _ = function_node; // TODO:
        //             return Declaration.Type.Void;
        //         },
        else => self.reportError("Unsupported node kind for inferType: {any}\n", .{node}),
    }
}

fn resolveType(self: *Semantic, node_index: u32) Declaration.Type {
    // TODO: Here lazy analisis
    const node = self.get(node_index);
    const node_name = node.string(self.file);
    if (Declaration.Type.lookup(node_name)) |t| {
        return t;
    } else if (self.getIfInScope(node_name)) |declaration| {
        const expression_child = self.get(declaration.node_index.? + 1); // TODO:
        const declaration_name = expression_child.string(self.file);
        if (Declaration.Type.lookup(declaration_name)) |t| {
            return t;
        } else if (self.getIfInScope(declaration_name)) |inner_declaration| {
            const inner_declaration_name = inner_declaration.node(self.file).?.string(self.file); // TODO:
            if (Declaration.Type.lookup(inner_declaration_name)) |t| {
                return t;
            }
            self.reportError("Type alias '{s}' does not refer to a primitive type\n", .{inner_declaration_name});
        }
        self.reportError("Type alias '{s}' does not refer to a primitive type\n", .{node_name});
    }
    self.reportError("Unknown type '{s}'\n", .{node_name});
}

fn functionNode(self: *Semantic) !void {
    const node_index = self.file.selected;
    self.advanceWithChildren();
    const node_name = self.get(node_index + 1).string(self.file);
    var current_scope = self.getCurrentScope();
    try current_scope.put(node_name, .{
        .kind = .Function,
        .symbol_type = .Function,
        .node_index = node_index,
    });
}

fn startAnalisisFromMain(self: *Semantic) !void {
    const main = self.file.global_scope.get("main") orelse {
        self.reportError("Function main not found\n", .{});
    };
    const main_index = main.node_index.?;
    const main_arguments = self.get(main_index + 2);
    if (main_arguments.children != 0) {
        self.reportError("Function main cannot take arguments\n", .{});
    }
    const main_allowed_return_types = .{ "void", "u8" };
    const main_return_type = self.get(main_index + 3).string(self.file);
    var is_one_of_allowed_return_types = false;
    inline for (main_allowed_return_types) |t| {
        if (!std.mem.eql(u8, main_return_type, t)) {
            is_one_of_allowed_return_types = true;
        }
    }
    if (!is_one_of_allowed_return_types) {
        self.reportError("Function main can only have {any} as return types, found {s}\n", .{ main_allowed_return_types, main_return_type });
    }

    try self.scopeNode(main_index + 4);
}

fn scopeNode(self: *Semantic, node_index: u32) Error!void {
    try self.file.scopes.append(self.allocator, .init(self.allocator));
    _ = node_index;
    // for () |child| {
    //     try self.semanticPass(child);
    // }
    _ = self.file.scopes.pop().?;
}

fn semanticPass(self: *Semantic) Error!void {
    const node = self.peek();
    switch (node.kind) {
        .Declaration => try self.declarationNode(),
        // .Scope => try self.scopeNode(),
        // .Call => try self.retvoidCallNode(node),
        else => self.reportError("Unsupported node: {any}\n", .{node}),
    }
}

// fn callNode(self: *Semantic, node: Node) Declaration {
//     const function_name = node.children[0].string(self.file.buffer, self.file.tokens.items);
//     self.printer.dprint("{s}\n", .{function_name});
//     const scope = self.scopeOf(function_name) orelse {
//         self.reportError(node.children[0], "function is not defined", .{}); // TODO:
//     };
//     const function = scope.get(function_name).?;
//     // TODO: check types of arguments
//     const arguments = node.children[1];
//     const parameters = function.expr.?.children[1];
//
//     if (arguments.children.len != parameters.children.len) {
//         self.reportError(node, "the amount of arguments does not match the defined ", .{});
//     }
//     if (arguments.children.len == 0) {
//         return function;
//     }
//     // TODO: add support for passing in types
//     for (arguments.children, parameters.children) |a, p| {
//         const parameter_type = blk: {
//             if (Declaration.Type.lookup(p.children[1].string(self.file.buffer, self.file.tokens.items))) |t| {
//                 break :blk t;
//             }
//             self.printer.dprint("custom type add support\n", .{});
//             @panic("AAAAA");
//         };
//
//         const argument_type = switch (a.kind) {
//             .IntLiteral => Declaration.Type.ComptimeInt,
//             .FloatLiteral => Declaration.Type.ComptimeFloat,
//             .Identifier => blk: {
//                 const argument_identifier = a.string(self.file.buffer, self.file.tokens.items);
//                 if (Declaration.Type.isPrimitive(argument_identifier)) {
//                     break :blk Declaration.Type.Type;
//                 }
//
//                 const argument_scope = self.scopeOf(argument_identifier) orelse {
//                     self.reportError(a, "identifier nod defined {s}", .{argument_identifier});
//                 };
//                 const argument_declaaration = argument_scope.get(argument_identifier).?;
//                 break :blk argument_declaaration.symbol_type;
//             },
//             else => unreachable,
//         };
//         if (!argument_type.canCastTo(parameter_type)) {
//             self.reportError(node, "types: {any} and {any} are not equal", .{ argument_type, parameter_type });
//         }
//     }
//     // TODO: add return type
//     // TODO: analize function body
//     for (function.expr.?.children[3].children) |body_node| {
//         // TODO: enter scope add arguments
//         // try self.semanticPass(body_node);
//         _ = body_node;
//     }
//
//     return function;
// }
//
// fn retvoidCallNode(self: *Semantic, node: Node) !void {
//     // TODO: check if returns void
//     // TODO: dissalow direct call from top level (no assing)
//     _ = self.callNode(node);
// }
