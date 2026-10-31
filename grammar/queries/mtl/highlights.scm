"fn" @keyword.function
"var" @keyword
"const" @keyword
"pub" @keyword
"return" @keyword
"and" @keyword.operator
"or" @keyword.operator
"not" @keyword.operator

"=" @operator
":=" @operator
"==" @operator
"!=" @operator
">" @operator
">=" @operator
"<" @operator
"<=" @operator
"+" @operator
"-" @operator
"*" @operator
"/" @operator
"%" @operator
"^" @operator

(end_of_statement) @punctuation.delimiter
":" @punctuation.delimiter
"," @punctuation.delimiter

"(" @punctuation.bracket
")" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket

(identifier) @variable
(type_identifier) @type
(bool_literal) @boolean

(integer_b2) @number
(integer_b8) @number
(integer_b16) @number
(integer_b10_normal) @number
(integer_b10_exponent) @number
(float_normal) @number.float
(float_exponent) @number.float

(comment) @comment

"@" @punctuation.special
(builtin_call (function_call (identifier) @function.builtin))
(function_call (identifier) @function.call)

