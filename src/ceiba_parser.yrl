%%
Header "%% THIS FILE IS AUTO-GENERATED BY YECC. "
"%% DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING.".

Nonterminals
    grammar
    expression expression_list expressions
    sign signed_number atom_expr
    binary_arg_list binary_args binary_container
    quote_expr backquote_expr unquote_expr unquote_splicing_expr
    value comma_value value_list values
    open_paren close_paren open_bracket close_bracket list_container
    open_curly close_curly tuple_container
    paired_comma_values paired_value_list paired_values unpaired_values open_bang_curly map_container
    open_percent_curly set_container
    %fun_reference
    .

Terminals
    identifier number binary_string list_string atom atom_safe atom_unsafe
    '(' ')' '[' ']' '{' '%{' '#{' '}'  '<<' '>>' ','
    '~@' '`' '\'' '~' '&' '.' '+' '-'
    .

Rootsymbol grammar.

%% MAIN FLOW OF EXPRESSIONS

grammar -> expressions : '$1'.
grammar -> '$empty' : nil.

% expression as represented in list format
expression -> value : '$1'.

expression_list -> expression : ['$1'].
expression_list -> expression_list expression : ['$2' | '$1'].

expressions -> expression_list : lists:reverse('$1').

%% Value

value       -> number : '$1'.
value       -> signed_number : '$1'.
value       -> binary_string : '$1'.
value       -> list_string : '$1'.
value       -> binary_container : '$1'.
value       -> identifier : '$1'.
value       -> atom_expr : '$1'.
value       -> list_container : '$1'.
value       -> tuple_container : '$1'.
value       -> map_container : '$1'.
value       -> set_container : '$1'.
value       -> quote_expr : '$1'.
value       -> backquote_expr : '$1'.
value       -> unquote_expr : '$1'.
value       -> unquote_splicing_expr : '$1'.

%% signed number
sign          -> '+' : '$1'.
sign          -> '-' : '$1'.
signed_number -> sign number : build_signed_number('$1', '$2').

%% atom
atom_expr     -> atom : build_atom('$1').
atom_expr     -> atom_safe : build_quoted_atom('$1', true).
atom_expr     -> atom_unsafe : build_quoted_atom('$1', false).

%% Macro syntaxs
quote_expr            -> '\'' value : build_quote('$1', '$2').
backquote_expr        -> '`' value : build_backquote('$1', '$2').
unquote_expr          -> '~' value : build_unquote('$1', '$2').
unquote_splicing_expr -> '~@' list_container : build_unquote_splicing('$1', '$2').

%%% Containers

%% Binary

binary_arg_list  -> binary_arg_list list_container : ['$2' | '$1'].

binary_args      -> binary_arg_list : lists:reverse('$1').
binary_args      -> values : ['$1'].

binary_container -> '<<' '>>' : build_binary('$1', []).
binary_container -> '<<' binary_args '>>' : build_binary('$1', '$2').

%% List

comma_value -> value : '$1'.
comma_value -> ',' value : '$2'.

value_list  -> value :  ['$1'].
value_list  -> value_list comma_value : ['$2' | '$1'].

values      -> value_list : lists:reverse('$1').

open_paren  -> '(' : '$1'.
close_paren -> ')' : '$1'.
open_bracket  -> '[' : '$1'.
close_bracket -> ']' : '$1'.

list_container -> open_bracket close_bracket : build_list('$1', []).
list_container -> open_bracket values close_bracket : build_list('$1', '$2').
list_container -> open_paren close_paren : build_list('$1', []).
list_container -> open_paren values close_paren: build_list('$1', '$2').

%% Tuple
open_curly   -> '{' : '$1'.
close_curly  -> '}' : '$1'.

tuple_container -> open_curly close_curly : build_tuple('$1', []).
tuple_container -> open_curly values close_curly: build_tuple('$1', '$2').

%% Map

paired_comma_values -> comma_value comma_value : ['$1', '$2'].

paired_value_list -> value comma_value : ['$1', '$2'].
paired_value_list -> paired_value_list paired_comma_values : lists:append('$2', '$1').

paired_values   -> paired_value_list : lists:reverse('$1').

unpaired_values -> value : ['$1'].
unpaired_values -> paired_comma_values comma_value : ['$2' | '$1'].

open_bang_curly -> '#{' : '$1'.

map_container -> open_bang_curly close_curly : build_map('$1', []).
map_container -> open_bang_curly paired_values close_curly : build_map('$1', '$2').
map_container -> open_bang_curly unpaired_values close_curly : throw_unpaired_map('$1').

%% Set

open_percent_curly -> '%{' : '$1'.

set_container -> open_percent_curly close_curly : build_set('$1', []).
set_container -> open_percent_curly values close_curly : build_set('$1', '$2').

%% function reference

%fun_reference -> identifier '.' identifier : -> build_fun_reference().

Erlang code.

-import(ceiba_scanner, [token_category/1,
                        token_line/1,
                        token_column/1,
                        token_symbol/1]).

build_meta(Token) ->
    [{line, token_line(Token)}, {column, token_column(Token)}].

build_atom(Token) ->
    token_symbol(Token).
%%    {atom, build_meta(Token), token_symbol(Token)}.

build_quoted_atom({_, _Meta, Bin}, Safe) when is_binary(Bin) ->
    Op = binary_to_atom_op(Safe),
    erlang:Op(Bin, utf8).

binary_to_atom_op(true)  -> binary_to_existing_atom;
binary_to_atom_op(false) -> binary_to_atom.


build_signed_number(Op, Number) ->
    {token_category(Op), build_meta(Op), Number}.

build_binary(Marker, Args) ->
    {binary, build_meta(Marker), Args}.

build_quote(Marker, Args) ->
    {quote, build_meta(Marker), Args}.

build_backquote(Marker, Args) ->
    {backquote, build_meta(Marker), Args}.

build_unquote(Marker, Args) ->
    {unquote, build_meta(Marker), Args}.

build_unquote_splicing(Marker, Args) ->
    {unquote_splicing, build_meta(Marker), Args}.

build_list(Marker, Args) ->
    {list, build_meta(Marker), Args}.

build_tuple(Marker, Args) ->
    {tuple, build_meta(Marker), Args}.

build_map(Marker, Args) ->
    {map, build_meta(Marker), Args}.

build_set(Marker, Args) ->
    {set, build_meta(Marker), Args}.

%% Errors
throw(Line, Error, Token) ->
    throw({error, {Line, ?MODULE, [Error, Token]}}).

throw_unpaired_map(Marker) ->
    throw(token_line(Marker), "unpaired values in map", token_symbol(Marker)).
