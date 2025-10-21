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
    for (self.file.scopes.items) |scope| {
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
        return self.file.scopes.items[self.file.scopes.items.len - 1];
    }
    return self.file.global_scope;
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
            else => self.reportError("Unsupported node for populateGlobalScope: {any}\n", .{node}),
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
    const declared_type = if (type_identifier.token_index) |_| self.resolveTypeIdentifier(type_index) else expression_type;
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
            // change for lazy analisis, as identifiers may not be in scope yet
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
            return self.inferType(node_index + 1);
        },
        .Call => {
            // const function_node = self.callNode(node);
            // _ = function_node; // TODO:
            return Declaration.Type.Void;
        },
        else => self.reportError("Unsupported node for inferType: {any}\n", .{node}),
    }
}

fn resolveTypeIdentifier(self: *Semantic, node_index: u32) Declaration.Type {
    // change for lazy analisis, as identifiers may not be in scope yet
    const node = self.get(node_index);
    const node_name = node.string(self.file);
    if (Declaration.Type.lookup(node_name)) |t| {
        return t;
    } else if (self.getIfInScope(node_name)) |declaration| {
        return self.resolveTypeIdentifier(declaration.node_index.? + 1);
    }
    self.reportError("Unknown type identifier '{s}'\n", .{node_name});
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

    self.file.selected = main_index + 4;
    try self.scopeNode();
}

fn scopeNode(self: *Semantic) Error!void {
    const scope = try File.makeScope(self.allocator);
    try self.file.scopes.append(self.allocator, scope);
    defer _ = self.file.scopes.pop().?;
    try self.file.all_scopes.append(self.allocator, scope);

    const node = self.peek();
    self.advance();
    var i: u32 = 0;
    while (i < node.children) : (i += 1) {
        try self.semanticPass();
    }
}

fn semanticPass(self: *Semantic) Error!void {
    const node = self.peek();
    switch (node.kind) {
        .Declaration => try self.declarationNode(),
        .Scope => try self.scopeNode(),
        .ExpressionStatement => try self.expressionStatementNode(),
        else => self.reportError("Unsupported node for semanticPass: {any}\n", .{node}),
    }
}

fn expressionStatementNode(self: *Semantic) !void {
    self.advance();
    const node = self.peek();
    switch (node.kind) {
        .Call => try self.callNode(),
        else => self.reportError("Unsupported node for expressioonStatement: {any}\n", .{node}),
    }
}

fn callNode(self: *Semantic) !void {
    // TODO: check returns
    self.advance();
    const function_indentifier = self.peek();
    const function_name = function_indentifier.string(self.file);
    const function = self.getIfInScope(function_name) orelse {
        self.reportError("Undefined function '{s}'\n", .{function_name});
    };

    const parameters_index = function.node_index.? + 1;
    const parameters = self.get(parameters_index);

    const arguments_index = self.file.selected;
    const arguments = self.peek();
    self.advanceWithChildren();

    if (arguments.children != parameters.children) {
        self.reportError("Number of arguments does not match number of parameters", .{});
    }

    // TODO: add support for passing in types as parameters, eg. fn a(T: type, a: T, b: T) T {...}
    if (arguments.children != 0) {
        for (1..arguments_index) |i_usize| {
            const i: u32 = @intCast(i_usize);
            self.printer.dprint("{any}\n", .{self.get(parameters_index + i)});
            self.printer.flush();
            const parameter_type = self.inferType(parameters_index + i);
            self.printer.dprint("{any}\n", .{parameter_type});
            self.printer.dprint("{any}\n", .{self.get(arguments_index + i)});
            self.printer.flush();
            const argument_type = self.inferType(arguments_index + i);
            self.printer.dprint("{any}\n", .{argument_type});
            self.printer.flush();
            if (!argument_type.canCastTo(parameter_type)) {
                self.reportError("Argument type: {any} cannot cast to parameter type: {any}\n", .{ argument_type, parameter_type });
            }
        }
    }

    const prev_selected = self.file.selected;
    self.file.selected = function.node_index.? + 4;
    // TODO: add arguments to the scope
    try self.scopeNode();
    self.file.selected = prev_selected;
    self.advance();
}
