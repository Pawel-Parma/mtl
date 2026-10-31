/// ! <reference types="tree-sitter-cli/dsl" />
// ! @ts-check

export default grammar({
    name: 'mtl',
    extras: $ => [
        /\s/,
        $.comment,
    ],
    word: $ => $.identifier,

    rules: {
        file: $ => repeat($.top_level_statement),

        top_level_statement: $ => choice(
            $.var_declaration,
            $.const_declaration,
            $.function_declaration,
            $.public_declaration
        ),

        public_declaration: $ => seq(
            'pub',
            choice(
                $.var_declaration,
                $.const_declaration,
                $.function_declaration
            )
        ),

        var_declaration: $ => seq(
            'var',
            $.identifier,
            choice(
                seq(':', $.type_expression),
                ':='
            ),
            $.expression,
            $.end_of_statement
        ),

        const_declaration: $ => seq(
            'const',
            $.identifier,
            optional(seq(':', $.type_expression)),
            '=',
            $.expression,
            $.end_of_statement
        ),

        function_declaration: $ => seq(
            'fn',
            $.identifier,
            '(',
            repeat(seq(
                $.identifier,
                ':',
                $.identifier,
                // TODO: make , optional only at the end 
                optional(',')
            )),
            ')',
            $.identifier,
            $.block
        ),

        statement: $ => choice(
            $.var_declaration,
            $.const_declaration,
            $.block,
            $.return,
            $.underscore_statement,
            $.expression_statement
        ),

        block: $ => seq(
            '{',
            repeat($.statement),
            '}'
        ),

        return: $ => seq(
            'return',
            optional($.expression),
            $.end_of_statement
        ),

        underscore_statement: $ => seq(
            '_',
            '=',
            $.expression,
            $.end_of_statement
        ),

        expression_statement: $ => seq(
            choice(
                seq($.identifier, $.modify_operator, $.expression),
                $.function_call,
                $.builtin_call
            ),
            $.end_of_statement
        ),

        end_of_statement: _ => ';',
        comment: _ => /\/\/[^\n]*/,

        type_expression: $ => choice(
            $.type_identifier,
            $.identifier,
            $.builtin_call
        ),

        expression: $ => choice(
            $.prefix_expression,
            $.infix_or_suffix_expression,
        ),

        prefix_expression: $ => choice(
            $.integer_literal,
            $.float_literal,
            $.bool_literal,
            $.identifier,
            $.unary_expression,
            $.grouping_expression,
            $.builtin_call,
        ),

        unary_expression: $ => prec(6, seq(
            $.unary_operator,
            $.expression,
        )),


        grouping_expression: $ => prec(7, seq('(', $.expression, ')')),

        builtin_call: $ => seq(
            '@',
            $.function_call
        ),

        infix_or_suffix_expression: $ => choice(
            $.binary_expression,
            $.function_call,
        ),

        binary_expression: $ => choice(
            prec.left(5, seq($.expression, choice('*', '/', '%'), $.expression)),
            prec.left(4, seq($.expression, choice('+', '-'), $.expression)),
            prec.left(3, seq($.expression, choice('==', '!=', '>', '>=', '<', '<='), $.expression)),
            prec.left(2, seq($.expression, 'and', $.expression)),
            prec.left(1, seq($.expression, '^', $.expression)),
            prec.left(0, seq($.expression, 'or', $.expression)),
        ),

        function_call: $ => prec(7, seq(
            $.identifier,
            '(',
            // TODO: make, optional only at the end 
            repeat(seq($.expression, optional(','))),
            ')'
        )),

        unary_operator: _ => choice('-', 'not'),
        modify_operator: _ => choice('=', '+=', '-=', '*=', '/=', '%='),

        type_identifier: _ => choice(
            'i8', 'i16', 'i32', 'i64', 'i128',
            'u8', 'u16', 'u32', 'u64', 'u128',
            'f16', 'f32', 'f64', 'f80', 'f128',
            'comptime_int', 'comptime_float', 'bool', 'void', 'type'
        ),

        identifier: _ => token(/([a-zA-Z][a-zA-Z0-9_]*|_[a-zA-Z0-9_]+)/),

        bool_literal: _ => choice('true', 'false'),

        integer_literal: $ => choice(
            $.integer_b2,
            $.integer_b8,
            $.integer_b16,
            $.integer_b10_normal,
            $.integer_b10_exponent
        ),

        integer_b2: _ => token(/0[bB][01]+(_[01]+)*/),
        integer_b8: _ => token(/0[oO][0-7]+(_[0-7]+)*/),
        integer_b16: _ => token(/0[xX][0-9a-fA-F]+(_[0-9a-fA-F]+)*/),
        integer_b10_normal: _ => token(/[0-9]+(_[0-9]+)*/),
        integer_b10_exponent: _ => token(/[0-9]+(_[0-9]+)*[eE][0-9]+(_[0-9]+)*/),

        float_literal: $ => choice(
            $.float_normal,
            $.float_exponent
        ),

        float_normal: _ => token(/[0-9]+(_[0-9]+)*\.[0-9]+(_[0-9]+)*/),
        float_exponent: _ => token(/[0-9]+(_[0-9]+)*(\.[0-9]+)?(_[0-9]+)*[eE](-)?[0-9]+(_[0-9]+)*/),
    }
});

