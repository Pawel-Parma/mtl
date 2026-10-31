(identifier) @variable

; TODO: delete and make user defined types be highlighed via lsp
(const_declaration
  (identifier) @type.definition
  (expression
    (prefix_expression
      (type_identifier))))

(const_declaration
  (identifier) @type.definition
  ":"
  (expression
    (prefix_expression
      (identifier) @type))
  "=")

(const_declaration
  (identifier) @type.definition
  ":"
  (expression
    (prefix_expression
      (identifier) @type))
  "=")

; end TODO
;
(type_identifier) @type

(underscore_statement
  "_" @variable.builtin)

[
  "var"
  "const"
] @keyword

"pub" @keyword.modifier

"fn" @keyword.function

"return" @keyword.return

[
  "and"
  "or"
  "not"
] @keyword.operator

(function_declaration
  (identifier) @function)

(function_declaration
  "("
  (identifier) @variable.parameter
  ":")

(function_call
  (identifier) @function.call)

(builtin_call) @function.builtin

(builtin_call
  (function_call
    (identifier) @function.builtin))

[
  "="
  ":="
  (modify_operator)
] @operator

[
  ":"
  ","
  (end_of_statement)
] @punctuation.delimiter

[
  "("
  ")"
  "{"
  "}"
] @punctuation.bracket

[
  "=="
  "!="
  ">"
  ">="
  "<"
  "<="
  "+"
  "-"
  "*"
  "/"
  "%"
  "^"
] @operator

(integer_literal) @number

(float_literal) @number.float

(bool_literal) @boolean

(comment) @comment
