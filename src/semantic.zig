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

pub const Error = error{
    UnexpectedEof,
    UnexpectedNode,
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, printer: Printer, file: *File) Semantic {
    return .{
        .allocator = allocator,
        .file = file,
        .printer = printer,
    };
}

pub fn analyze(self: *Semantic) !void {
    try self.file.scopes.append(self.allocator, .init(self.allocator));
    // TODO: make global scope lazily analyzed
    try self.populateGlobalScope();
    // try self.checkMain();
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

inline fn isAtEnd(self: *Semantic) bool {
    return self.file.selected >= self.file.ast.items.len;
}

fn checkEof(self: *Semantic) void {
    if (self.isAtEnd()) {
        self.reportError("Unexpected end of file\n", .{});
    }
}

fn scopeOf(self: *Semantic, identifier: []const u8) ?*std.StringHashMap(Declaration) {
    if (self.file.global_scope.contains(identifier)) {
        return &self.file.global_scope;
    }
    for (self.file.scopes.items) |*scope| {
        if (scope.contains(identifier)) {
            return scope;
        }
    }
    return null;
}

inline fn isInScope(self: *Semantic, identifier: []const u8) bool {
    return self.scopeOf(identifier) != null;
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
        // self.printer.dprint("{any}\n", .{node});
        self.printer.flush();
        switch (node.kind) {
            .Declaration => try self.declarationNode(),
            // .Function => try self.functionNode(),
            .Function => {
                self.advanceWithChildren();
            },
            else => self.reportError("Unexpected node : {any}", .{node}),
        }
    }
}

fn declarationNode(self: *Semantic) !void {
    const declaration = self.peek();
    self.advance();

    const identifier_name = self.peek().string(self.file);
    self.advance();
    if (Declaration.Type.isPrimitive(identifier_name)) {
        self.reportError("Cannot declare variable '{s}', shadows primitive type", .{identifier_name});
    }
    if (self.isInScope(identifier_name)) {
        self.reportError("Cannot declare variable '{s}', shadows declaration", .{identifier_name});
    }

    const type_identifier = self.peek();
    self.advance();

    const expression = self.peek();
    const expression_index = self.file.selected;
    self.advanceWithChildren();

    const expression_type = self.inferType(expression);
    const declared_type = if (type_identifier.token_index) |_| self.resolveType(type_identifier) else expression_type;
    if (!declared_type.equals(expression_type)) {
        self.reportError("Type mismatch in declaration of '{s}', expected {any}, got {any}\n", .{ identifier_name, declared_type, expression_type });
    }

    // var current_scope = self.getCurrentScope();
    const kind: Declaration.Kind = if (declaration.token(self.file).?.kind == .Const) .Const else .Var;
    try self.file.global_scope.put(identifier_name, .{
        .kind = kind,
        .symbol_type = declared_type,
        .node_index = expression_index,
    });
}

fn inferType(self: *Semantic, node: Node) Declaration.Type {
    _ = self;
    _ = node;
    return Declaration.Type.Bool;
}

fn resolveType(self: *Semantic, node: Node) Declaration.Type {
    _ = self;
    _ = node;
    return Declaration.Type.Bool;
}

// fn inferType(self: *Semantic, node: Node) Declaration.Type {
//     const name = node.string(self.file.buffer, self.file.tokens.items);
//     switch (node.kind) {
//         .IntLiteral => return .ComptimeInt,
//         .FloatLiteral => return .ComptimeFloat,
//         .UnaryMinus => {
//             const child_type = self.inferType(node.children[0]);
//             if (!child_type.allowsOperation(.UnaryMinus)) {
//                 self.reportError(node, "Unary minus is not allowed on type {any}", .{child_type});
//             }
//             return child_type;
//         },
//         .BinaryPlus, .BinaryMinus, .BinaryStar, .BinarySlash => {
//             const left_type = self.inferType(node.children[0]);
//             const right_type = self.inferType(node.children[1]);
//             if (left_type.equals(right_type)) {
//                 if (!left_type.allowsOperation(node.kind)) {
//                     self.reportError(node, "Operation {any} is not allowed on type {any}", .{ node.kind, left_type });
//                 }
//                 if (!right_type.allowsOperation(node.kind)) {
//                     self.reportError(node, "Operation {any} is not allowed on type {any}", .{ node.kind, right_type });
//                 }
//                 return left_type;
//             }
//             self.reportError(node, "Type mismatch in binary operator, expected {any}, got {any}", .{ left_type, right_type });
//         },
//         .Identifier => {
//             if (Declaration.Type.isPrimitive(name)) {
//                 return .Type;
//             }
//             if (self.scopeOf(name)) |scope| {
//                 return scope.get(name).?.symbol_type;
//             }
//             self.reportError(node, "Undefined identifier '{s}'", .{name});
//         },
//         .Expression => {
//             const first_expr_type = self.inferType(node.children[0]);
//             for (node.children) |expr| {
//                 const expr_type = self.inferType(expr);
//                 if (!first_expr_type.equals(expr_type)) {
//                     self.reportError(node, "Type mismatch in expression, expected {any}, got {any}", .{ first_expr_type, expr_type });
//                 }
//             }
//             return first_expr_type;
//         },
//         .Call => {
//             const function_node = self.callNode(node);
//             _ = function_node; // TODO:
//             return Declaration.Type.Void;
//         },
//         else => self.reportError(node, "Unsupported node kind for inferType: {any}", .{node}),
//     }
// }
//
// fn resolveType(self: *Semantic, type_node: Node) Declaration.Type {
//     const type_name = type_node.string(self.file.buffer, self.file.tokens.items);
//     if (Declaration.Type.lookup(type_name)) |t| {
//         return t;
//     } else {
//         if (self.scopeOf(type_name)) |scope_map| {
//             const declaration = scope_map.get(type_name).?;
//             const declaration_name = declaration.expr.?.string(self.file.buffer, self.file.tokens.items);
//             if (Declaration.Type.lookup(declaration_name)) |t| {
//                 return t;
//             } else if (self.scopeOf(declaration_name)) |scope| {
//                 const inner_declaration = scope.get(declaration_name).?;
//                 const inner_declaration_name = inner_declaration.expr.?.string(self.file.buffer, self.file.tokens.items);
//                 if (Declaration.Type.lookup(inner_declaration_name)) |t| {
//                     return t;
//                 }
//                 self.reportError(type_node, "Type alias '{s}' does not refer to a primitive type\n", .{inner_declaration_name});
//             } else {
//                 self.reportError(type_node, "Type alias '{s}' does not refer to a primitive type\n", .{type_name});
//             }
//         } else {
//             self.reportError(type_node, "Unknown type '{s}'\n", .{type_name});
//         }
//     }
// }
// fn checkMain(self: *Semantic) !void {
// const main = try self.getMain();
// if (main.children[1].children.len != 0) {
//     self.reportError(main.children[1], "Function main cannot take arguments", .{});
// }
// const allowed_main_types = .{ "void", "u8" };
// const main_type = main.children[2].string(self.file.buffer, self.file.tokens.items);
// var is_one_of_allowed_types = false;
// inline for (allowed_main_types) |t| {
//     if (!std.mem.eql(u8, main_type, t)) {
//         is_one_of_allowed_types = true;
//     }
// }
// if (!is_one_of_allowed_types) {
//     self.reportError(main.children[2], "function main can only have {any} as return type, found {s}", .{ allowed_main_types, main_type });
// }
//
// for (main.children[3].children) |node| {
//     try self.semanticPass(node);
// }
// }
// fn semanticPass(self: *Semantic, node: Node) Error!void {
//     switch (node.kind) {
//         .Declaration => try self.declarationNode(node),
//         .Scope => try self.scopeNode(node),
//         .Function => try self.functionNode(node),
//         .Call => try self.retvoidCallNode(node),
//         else => self.reportError(node, "Unsupported node in semanticPass: {any}", .{node}),
//     }
// }
//
//
// fn reportError(self: *Semantic, node: Node, comptime fmt: []const u8, args: anytype) noreturn {
//     const len = self.file.buffer.len;
//     const token = node.token(self.file.tokens.items) orelse {
//         self.printer.printSourceLine(fmt ++ "\n", args, self.file, 0, 0, "NULL NODE", 9);
//         @panic("10 nn");
//     };
//     const line_info = self.file.lineInfo(token);
//     const column_number = token.start - line_info.start;
//     const line = File.getLine(self.file.buffer, line_info.start, token.start, len);
//
//     self.printer.printSourceLine(fmt ++ "\n", args, self.file, line_info.number, column_number, line, token.len());
//     self.printer.print("Tokenization failed", .{});
//     @panic("10");
// }
//
// fn scopeOf(self: *Semantic, name: []const u8) ?*std.StringHashMap(Declaration) {
//     for (self.file.scopes.items) |*scope_map| {
//         if (scope_map.contains(name)) {
//             return scope_map;
//         }
//     }
//     return null;
// }
//
// inline fn isInScope(self: *Semantic, name: []const u8) bool {
//     return self.scopeOf(name) != null;
// }
//
// fn getMain(self: *Semantic) !Node {
//     for (self.file.ast.items) |node| {
//         if (node.kind == .Function) {
//             if (std.mem.eql(u8, node.children[0].string(self.file.buffer, self.file.tokens.items), "main")) {
//                 return node;
//             }
//         }
//     }
//     self.reportError(.{ .kind = .Function, .children = &.{}, .token_index = null }, "", .{});
// }
//
// fn functionNode(self: *Semantic, node: Node) !void {
//     const string = node.children[0].string(self.file.buffer, self.file.tokens.items);
//     self.printer.dprint("adding: {s}\n", .{string});
//     const declaration: Declaration = .{ .kind = .Function, .symbol_type = .Function, .expr = node };
//     try self.file.scopes.items[0].put(string, declaration);
// }
//
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
//
// fn scopeNode(self: *Semantic, node: Node) Error!void {
//     try self.file.scopes.append(self.allocator, .init(self.allocator));
//     for (node.children) |child| {
//         try self.semanticPass(child);
//     }
//     var last_scope = self.file.scopes.pop().?;
//     last_scope.deinit();
// }
//
