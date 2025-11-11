const std = @import("std");

const options = @import("options.zig");
const Printer = @import("printer.zig");
const File = @import("file.zig");
const Token = @import("token.zig");
const Node = @import("node.zig");
const Declaration = @import("declaration.zig");
// TODO: refactor for more safety, use self.expect

const Semantic = @This();
allocator: std.mem.Allocator,
printer: Printer,
file: *File,

pub const Error = error{
    ParsingFailed,
} || std.mem.Allocator.Error;

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
    try self.startAnalysisFromMain();
    self.file.printScopes();
}

inline fn advance(self: *Semantic) void {
    self.file.selected += 1;
}

fn toAdvanceWithChildren(self: *Semantic, node_index: u32) u32 {
    var to_advance = self.get(node_index).children;
    var selected = node_index + 1;
    while (!self.isIndexAtEnd(selected) and to_advance != 0) {
        to_advance += self.get(selected).children;
        to_advance -= 1;
        selected += 1;
    }
    return selected - node_index;
}

fn advanceWithChildren(self: *Semantic) void {
    const to_advance = self.toAdvanceWithChildren(self.file.selected);
    self.file.selected += to_advance;
}

inline fn peek(self: *Semantic) Node {
    return self.file.ast.items[self.file.selected];
}

inline fn get(self: *Semantic, node_index: u32) Node {
    return self.file.ast.items[node_index];
}

inline fn isIndexAtEnd(self: *Semantic, token_index: u32) bool {
    return token_index >= self.file.ast.items.len;
}

inline fn isAtEnd(self: *Semantic) bool {
    return self.isIndexAtEnd(self.file.selected);
}

fn getIfInScope(self: *Semantic, identifier: []const u8) ?Declaration {
    if (self.file.global_scope.get(identifier)) |id| {
        return id;
    }
    var i: usize = self.file.scopes.items.len;
    while (i > 1) : (i -= 1) {
        const scope = self.file.scopes.items[i - 1];
        if (scope.get(identifier)) |id| {
            return id;
        }
    }
    return null;
}

fn getPtrIfInScope(self: *Semantic, identifier: []const u8) ?*Declaration {
    if (self.file.global_scope.getPtr(identifier)) |id| {
        return id;
    }
    var i: usize = self.file.scopes.items.len;
    while (i > 1) : (i -= 1) {
        const scope = self.file.scopes.items[i - 1];
        if (scope.getPtr(identifier)) |id| {
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
        return self.file.scopes.items[self.file.scopes.items.len - 1];
    }
    return self.file.global_scope;
}

fn reportError(self: *Semantic, comptime fmt: []const u8, args: anytype) Error {
    self.printer.print(fmt, args);
    self.printer.flush();
    if (options.debug) {
        @panic("Stack Trace!!!\n");
    }
    return Error.ParsingFailed;
}

fn populateGlobalScope(self: *Semantic) Error!void {
    while (!self.isAtEnd()) {
        const node = self.peek();
        switch (node.kind) {
            .Declaration => try self.declarationNode(false),
            .Function => try self.functionNode(false),
            .Public => try self.publicNode(),
            else => return self.reportError("Unsupported node for populateGlobalScope: {any}\n", .{node}),
        }
    }
}

fn declarationNode(self: *Semantic, comptime is_public: bool) !void {
    const declaration = self.peek();
    self.advance();

    const identifier_name = self.peek().string(self.file);
    self.advance();
    if (Declaration.Type.isPrimitive(identifier_name)) {
        return self.reportError("Cannot declare variable '{s}', shadows primitive type\n", .{identifier_name});
    }
    if (self.isInScope(identifier_name)) {
        return self.reportError("Cannot declare variable '{s}', shadows declaration\n", .{identifier_name});
    }

    const type_identifier = self.peek();
    const type_index = self.file.selected;
    self.advance();

    const expression_index = self.file.selected;
    self.advanceWithChildren();

    const expression_type = try self.inferType(expression_index);
    const declared_type = if (type_identifier.token_index) |_| try self.resolveTypeIdentifier(type_index) else expression_type;
    if (!declared_type.equals(expression_type)) {
        return self.reportError("Type mismatch in declaration of '{s}', expected {any}, got {any}\n", .{ identifier_name, declared_type, expression_type });
    }

    var current_scope = self.getCurrentScope();
    const kind: Declaration.Kind = switch (declaration.token(self.file).?.kind) {
        .Const => if (is_public) .PubConst else .Const,
        .Var => if (is_public) .PubVar else .Var,
        else => unreachable,
    };
    if ((kind == .Var or kind == .PubVar) and declared_type == .Type) {
        return self.reportError("variable {s} of type {any} must be const\n", .{ identifier_name, expression_type });
    }
    try current_scope.put(identifier_name, .{
        .kind = kind,
        .symbol_type = declared_type,
        .node_index = expression_index,
    });
}

fn inferType(self: *Semantic, node_index: u32) Error!Declaration.Type {
    const node = self.get(node_index);
    switch (node.kind) {
        .IntLiteral, .IntBinaryLiteral, .IntOctalLiteral, .IntHexadecimalLiteral, .IntScientificLiteral => return .ComptimeInt,
        .FloatLiteral, .FloatScientificLiteral => return .ComptimeFloat,
        .TrueLiteral, .FalseLiteral => return .Bool,
        .UnaryMinus, .UnaryNot => {
            const child_type = try self.inferType(node_index + 1);
            if (!child_type.allowsOperation(node.kind)) {
                return self.reportError("Operation {any} is not allowed on type {any}\n", .{ node.kind, child_type });
            }
            return child_type;
        },
        .BinaryPlus, .BinaryMinus, .BinaryStar, .BinarySlash, .BinaryPercent, .BinaryDoubleEquals, .BinaryBangEquals, .BinaryGraterThan, .BinaryGraterEqualsThan, .BinaryLesserThan, .BinaryLesserEqualsThan, .BinaryAnd, .BinaryOr, .BinaryCaret => {
            const left_type = try self.inferType(node_index + 1);
            const right_type = try self.inferType(node_index + 1 + self.toAdvanceWithChildren(node_index + 1));
            if (!left_type.equals(right_type)) {
                return self.reportError("Type mismatch in binary operator, expected {any}, got {any}\n", .{ left_type, right_type });
            }
            if (!left_type.allowsOperation(node.kind)) {
                return self.reportError("Operation {any} is not allowed on type {any}\n", .{ node.kind, left_type });
            }
            if (!right_type.allowsOperation(node.kind)) {
                return self.reportError("Operation {any} is not allowed on type {any}\n", .{ node.kind, right_type });
            }

            return switch (node.kind) {
                .BinaryDoubleEquals, .BinaryBangEquals, .BinaryGraterThan, .BinaryGraterEqualsThan, .BinaryLesserThan, .BinaryLesserEqualsThan, .BinaryAnd, .BinaryOr => .Bool,
                else => Declaration.Type.subsetType(left_type, right_type) catch {
                    return self.reportError("Types {any}, {any} are not compatible\n", .{ node.kind, right_type });
                },
            };
        },
        .Identifier => {
            const node_name = node.string(self.file);
            if (Declaration.Type.isPrimitive(node_name)) {
                return .Type;
            }
            // change for lazy analysis, as identifiers may not be in scope yet
            if (self.getPtrIfInScope(node_name)) |declaration| {
                declaration.used = true;
                return declaration.symbol_type;
            }
            return self.reportError("Undefined identifier '{s}'\n", .{node_name});
        },
        .Expression, .Grouping => return self.inferType(node_index + 1),
        .Call => {
            const prev_selected = self.file.selected;
            self.file.selected = node_index;
            const function_type = try self.callNode(null);
            self.file.selected = prev_selected;
            return function_type;
        },
        else => return self.reportError("Unsupported node for inferType: {any}\n", .{node}),
    }
}

fn resolveTypeIdentifier(self: *Semantic, node_index: u32) !Declaration.Type {
    // change for lazy analysis, as identifiers may not be in scope yet
    const node = self.get(node_index);
    const node_name = node.string(self.file);
    if (Declaration.Type.lookup(node_name)) |t| {
        return t;
    } else if (self.getIfInScope(node_name)) |declaration| {
        return self.resolveTypeIdentifier(declaration.node_index.? + 1);
    }
    return self.reportError("Unknown type identifier '{s}'\n", .{node_name});
}

fn functionNode(self: *Semantic, is_public: bool) !void {
    const kind: Declaration.Kind = if (is_public) .PubFn else .Fn;
    const node_index = self.file.selected;
    self.advance();
    const node_name = self.peek().string(self.file);
    self.advance();
    self.advanceWithChildren();
    const symbol_type = Declaration.Type.lookup(self.peek().string(self.file)) orelse .NotAnalized;
    self.advance();
    self.advanceWithChildren();
    var current_scope = self.getCurrentScope();
    try current_scope.put(node_name, .{
        .kind = kind,
        .symbol_type = symbol_type,
        .node_index = node_index,
    });
}

fn publicNode(self: *Semantic) !void {
    self.advance();
    const node = self.peek();
    switch (node.kind) {
        .Declaration => try self.declarationNode(true),
        .Function => try self.functionNode(true),
        else => return self.reportError("Unsupported node for publicNode: {any}\n", .{node}),
    }
}

fn startAnalysisFromMain(self: *Semantic) !void {
    const main = self.file.global_scope.get("main") orelse {
        return self.reportError("Function main not found\n", .{});
    };

    if (main.kind != .PubFn) {
        return self.reportError("Function main has to be public\n", .{});
    }

    const main_index = main.node_index.?;
    const main_arguments = self.get(main_index + 2);
    if (main_arguments.children != 0) {
        return self.reportError("Function main cannot take arguments\n", .{});
    }
    const main_allowed_return_types = .{ "void", "u8" };
    const main_return_type = self.get(main_index + 3).string(self.file);
    var is_one_of_allowed_return_types = false;
    inline for (main_allowed_return_types) |t| {
        if (std.mem.eql(u8, main_return_type, t)) {
            is_one_of_allowed_return_types = true;
            break;
        }
    }
    if (!is_one_of_allowed_return_types) {
        return self.reportError("Function main can only have {any} as return types, found {s}\n", .{ main_allowed_return_types, main_return_type });
    }

    self.file.selected = main_index;
    _ = try self.callNode(null);
}

fn scopeNode(self: *Semantic) Error!void {
    const scope = try File.makeScope(self.allocator);
    try self.file.appendScope(scope);
    defer self.file.popScope();

    const node = self.peek();
    self.advance();
    var i: u32 = 0;
    while (i < node.children) : (i += 1) {
        try self.semanticPass();
    }
    try self.checkScopeVarUsage(false);
}

fn semanticPass(self: *Semantic) Error!void {
    const node = self.peek();
    switch (node.kind) {
        .Declaration => try self.declarationNode(false),
        .Scope => try self.scopeNode(),
        .ExpressionStatement => try self.expressionStatementNode(),
        .Return => try self.returnNode(),
        .IgnoreResult => try self.ignoreResult(),
        else => return self.reportError("Unsupported node for semanticPass: {any}\n", .{node}),
    }
}

fn expressionStatementNode(self: *Semantic) !void {
    self.advance();
    const node = self.peek();
    switch (node.kind) {
        .Call => _ = try self.callNode(.Void),
        .Mutation => try self.mutationNode(),
        else => return self.reportError("Unsupported node for expressionStatement: {any}\n", .{node}),
    }
}

fn callNode(self: *Semantic, required_type: ?Declaration.Type) !Declaration.Type {
    // TODO: support recursion
    self.advance();
    const function_indentifier = self.peek();
    self.advance();
    const function_name = function_indentifier.string(self.file);
    const declaration = self.getIfInScope(function_name) orelse {
        return self.reportError("Undefined function '{s}'\n", .{function_name});
    };

    if (declaration.kind != .Fn and declaration.kind != .PubFn) {
        return self.reportError("'{s}' is not a function\n", .{function_name});
    }

    const function_index = declaration.node_index.?;
    const function_type_index = function_index + 2 + self.toAdvanceWithChildren(function_index + 2);
    const function_type_identifier = self.get(function_type_index);
    const function_type = Declaration.Type.lookup(function_type_identifier.string(self.file)) orelse {
        return self.reportError("{any} is not a primitive type\n", .{function_type_identifier});
    };
    if (required_type != null and !function_type.equals(required_type.?)) {
        return self.reportError("value of type {any} ignored\n", .{function_type});
    }

    const parameters_index = declaration.node_index.? + 2;
    const parameters = self.get(parameters_index);

    const arguments_index = self.file.selected;
    const arguments = self.peek();
    self.advanceWithChildren();

    if (arguments.children != parameters.children) {
        return self.reportError("Number of arguments does not match number of parameters", .{});
    }

    // TODO: add support for passing in types as parameters, eg. fn a(T: type, a: T, b: T) T {...}, same as lazy analysis
    const parameters_scope = try File.makeScope(self.allocator);
    var i: u32 = 1;
    var j: u32 = 1;
    while (i < arguments.children * 3) {
        const parameter_identifier = self.get(parameters_index + i + 1);
        const parameter_name = parameter_identifier.string(self.file);
        if (self.file.global_scope.contains(parameter_name)) {
            return self.reportError("Cannot declare variable '{s}', shadows declaration\n", .{parameter_name});
        }
        const parameter_identifier_type = self.get(parameters_index + i + 2);
        const parameter_type = Declaration.Type.lookup(parameter_identifier_type.string(self.file)) orelse {
            return self.reportError("{any} is not a primitive type\n", .{parameter_identifier_type});
        };
        const argument_type = try self.inferType(arguments_index + j + 1);
        if (!argument_type.canCastTo(parameter_type)) {
            return self.reportError("argument type: {any} cannot cast to parameter type: {any}\n", .{ argument_type, parameter_type });
        }
        try parameters_scope.put(parameter_name, .{
            .kind = .Var,
            .symbol_type = parameter_type,
            .node_index = parameters_index + i,
        });
        i += 3;
        j += self.toAdvanceWithChildren(arguments_index + j);
    }

    const prev_selected = self.file.selected;
    self.file.selected = declaration.node_index.? + 3 + self.toAdvanceWithChildren(declaration.node_index.? + 2);
    // TODO: change scope so non globals can be redclared
    try self.file.appendScope(parameters_scope);
    try self.scopeNode();
    try self.checkScopeVarUsage(true);
    self.file.popScope();
    self.file.selected = prev_selected;

    return function_type;
}

fn checkScopeVarUsage(self: *Semantic, is_function_scope: bool) !void {
    const scope = self.getCurrentScope();
    var iterator = scope.iterator();
    while (iterator.next()) |entry| {
        const declaration = entry.value_ptr;
        const name = entry.key_ptr.*;
        switch (declaration.kind) {
            .Const => {
                if (declaration.used == false) {
                    return self.reportError("'{s}' declared but never used\n", .{name});
                }
            },
            .Var => {
                if (declaration.used == false) {
                    return self.reportError("'{s}' declared but never used\n", .{name});
                }
                if (declaration.muated == false and !is_function_scope) {
                    return self.reportError("'{s}' declared as var but never mutated\n", .{name});
                }
            },
            .Fn, .PubConst, .PubVar, .PubFn => unreachable,
        }
    }
}

fn mutationNode(self: *Semantic) !void {
    self.advance();
    const identifier_node = self.peek();
    const identifier_name = identifier_node.string(self.file);
    self.advance();
    const identifier_declaration = self.getPtrIfInScope(identifier_name) orelse {
        return self.reportError("Undefined identifier '{s}'\n", .{identifier_name});
    };
    if (identifier_declaration.kind == .Const or identifier_declaration.kind == .PubConst) {
        return self.reportError("Cannot assign to constant {s}\n", .{identifier_name});
    }
    identifier_declaration.muated = true;
    identifier_declaration.used = true;

    const operation_node = self.peek();
    self.advance();
    if (!identifier_declaration.symbol_type.allowsOperation(operation_node.kind)) {
        return self.reportError("Operation {any} is not allowed on type {any}\n", .{ operation_node.kind, identifier_declaration.symbol_type });
    }
    const expression_node_index = self.file.selected;
    const expression_type = try self.inferType(expression_node_index);
    self.advanceWithChildren();
    if (!expression_type.allowsOperation(operation_node.kind)) {
        return self.reportError("Operation {any} is not allowed on type {any}\n", .{ operation_node.kind, identifier_declaration.symbol_type });
    }
    if (!expression_type.canCastTo(identifier_declaration.symbol_type)) {
        return self.reportError("Type mismatch in mutation operator, expected {any}, got {any}\n", .{ identifier_declaration.symbol_type, expression_type });
    }
}

fn returnNode(self: *Semantic) !void {
    // TODO: analyze return type
    const node = self.peek();
    self.advance();
    if (node.children == 1) {
        _ = try self.inferType(self.file.selected);
        self.advanceWithChildren();
    }
    self.printer.dprintanyn(node);
}

fn ignoreResult(self: *Semantic) !void {
    self.advance();
    self.advance();
    _ = try self.inferType(self.file.selected);
    self.advanceWithChildren();
}
