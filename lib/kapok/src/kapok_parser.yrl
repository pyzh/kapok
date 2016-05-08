%%
Header "%% THIS FILE IS AUTO-GENERATED BY YECC. "
"%% DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING.".

Nonterminals
    grammar
    expression expression_list expressions
    number sign signed_number atom_expr
    bitstring_arg_list bitstring_args bitstring_container
    quote_expr backquote_expr unquote_expr unquote_splicing_expr
    value comma_value value_list values
    open_paren close_paren open_bracket close_bracket list_container
    open_curly close_curly tuple_container
    paired_comma_values paired_value_list paired_values unpaired_values open_bang_curly map_container
    open_percent_curly set_container
    dot_op dot_identifier function_identifier
    .

Terminals
    hex_number base_number char_number integer float
    binary_string list_string atom atom_safe atom_unsafe identifier
    '(' ')' '[' ']' '{' '%{' '#{' '}'  '<<' '>>' ','
    unquote_splicing backquote quote unquote rest '.' '/' '+' '-'
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

%% Literals
%% number
number      -> hex_number : build_number('$1').
number      -> base_number : build_number('$1').
number      -> char_number : build_number('$1').
number      -> integer : build_number('$1').
number      -> float : build_number('$1').

value       -> number : '$1'.
value       -> signed_number : '$1'.
%% atom
value       -> atom_expr : '$1'.
%% identifier
value       -> dot_identifier : '$1'.
value       -> function_identifier: '$1'.
%% macro syntax
value       -> quote_expr : '$1'.
value       -> backquote_expr : '$1'.
value       -> unquote_expr : '$1'.
value       -> unquote_splicing_expr : '$1'.
%% strings
value       -> binary_string : '$1'.
value       -> list_string : '$1'.
%% containers
value       -> bitstring_container : '$1'.
value       -> list_container : '$1'.
value       -> tuple_container : '$1'.
value       -> map_container : '$1'.
value       -> set_container : '$1'.

%% signed number
sign           -> '+' : '$1'.
sign           -> '-' : '$1'.
signed_number  -> sign number : build_signed_number('$1', '$2').

%% atom
atom_expr      -> atom : build_atom('$1').
atom_expr      -> atom_safe : build_quoted_atom('$1', true).
atom_expr      -> atom_unsafe : build_quoted_atom('$1', false).

%% identifier
dot_op         -> '.' : '$1'.

dot_identifier -> identifier : '$1'.
dot_identifier -> identifier dot_op identifier : build_dot('$2', '$1', '$3').
dot_identifier -> dot_identifier dot_op identifier : build_dot('$2', '$1', '$3').

%% function_identifier
function_identifier -> identifier '/' integer : build_function_identifier('$1', '$3').

%% Macro syntaxs
quote_expr            -> quote value : build_quote('$1', '$2').
backquote_expr        -> backquote value : build_backquote('$1', '$2').
unquote_expr          -> unquote value : build_unquote('$1', '$2').
unquote_splicing_expr -> unquote_splicing list_container : build_unquote_splicing('$1', '$2').

%%% Containers

%% Bitstring

bitstring_arg_list  -> bitstring_arg_list list_container : ['$2' | '$1'].

bitstring_args      -> bitstring_arg_list : lists:reverse('$1').
bitstring_args      -> values : '$1'.

bitstring_container -> '<<' '>>' : build_bitstring('$1', []).
bitstring_container -> '<<' bitstring_args '>>' : build_bitstring('$1', '$2').

%% List

comma_value -> value : '$1'.
comma_value -> ',' value : '$2'.

value_list  -> value :  ['$1'].
value_list  -> value_list comma_value : ['$2' | '$1'].

values      -> value_list : lists:reverse('$1').

open_bracket  -> '[' : '$1'.
close_bracket -> ']' : '$1'.
open_paren  -> '(' : '$1'.
close_paren -> ')' : '$1'.

list_container -> open_bracket close_bracket : build_literal_list('$1', []).
list_container -> open_bracket values close_bracket : build_literal_list('$1', '$2').
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

Erlang code.

-import(kapok_scanner, [token_category/1,
                        token_meta/1,
                        token_symbol/1]).
-include("kapok.hrl").

build_number(Token) ->
  {number, token_meta(Token), token_symbol(Token)}.

build_signed_number(Op, Number) ->
  {token_category(Op), token_meta(Op), Number}.

build_atom(Token) ->
  {atom, token_meta(Token), token_symbol(Token)}.

build_quoted_atom(Token, Safe) ->
  Op = binary_to_atom_op(Safe),
  {atom, token_meta(Token), erlang:Op(token_symbol(Token), utf8)}.

binary_to_atom_op(true)  -> binary_to_existing_atom;
binary_to_atom_op(false) -> binary_to_atom.

build_function_identifier(FunctionName, Arity) ->
  {function_id, token_meta(FunctionName), {FunctionName, Arity}}.

build_dot(Dot, Left, Right) ->
  {dot, token_meta(Dot), [Left, Right]}.

build_bitstring(Marker, Args) ->
  {bitstring, token_meta(Marker), Args}.

build_quote(Marker, Args) ->
  {quote, token_meta(Marker), Args}.

build_backquote(Marker, Args) ->
  {backquote, token_meta(Marker), Args}.

build_unquote(Marker, Args) ->
  {unquote, token_meta(Marker), Args}.

build_unquote_splicing(Marker, Args) ->
  {unquote_splicing, token_meta(Marker), Args}.

build_literal_list(Marker, Args) ->
  {literal_list, token_meta(Marker), Args}.

build_list(Marker, Args) ->
  {list, token_meta(Marker), Args}.

build_tuple(Marker, Args) ->
  {tuple, token_meta(Marker), Args}.

build_map(Marker, Args) ->
  {map, token_meta(Marker), Args}.

build_set(Marker, Args) ->
  {set, token_meta(Marker), Args}.

%% Errors
throw(Line, Error, Token) ->
  throw({error, {Line, ?MODULE, [Error, Token]}}).

throw_unpaired_map(Marker) ->
  throw(?line(token_meta(Marker)), "unpaired values in map", token_symbol(Marker)).
