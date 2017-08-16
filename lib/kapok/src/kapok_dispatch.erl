%% Helper module for dispatching names(module/function/macro/var) and their references.
-module(kapok_dispatch).
-export([default_requires/0,
         default_uses/0,
         find_local_macro/3,
         find_remote_macro/4,
         find_local/2,
         find_local_function/3,
         get_remote_function/4,
         find_remote_function/4,
         format_error/1]).
-import(kapok_config, [get_compiler_opt/1]).
-include("kapok.hrl").

default_requires() ->
  L = ['kapok_macro',
       'core'],
  orddict:from_list(lists:map(fun(X) -> {X, X} end, L)).

default_uses() ->
  ['core'].

%% find local/remote macro/function

find_local_macro(Meta, FunArity, #{namespace := Namespace} = Env) ->
  %% check whether the FunArity refers to a macro in current namespace
  %% which is defined previously.
  Macros = kapok_symbol_table:namespace_macros(Namespace),
  case filter_fa(FunArity, Macros) of
    [{F, A, P}] ->
      {{F, A, P}, Env};
    [] ->
      find_import_macro(Meta, FunArity, Env)
  end.

find_import_macro(Meta, FunArity, Env) ->
  {D, Env1} = find_dispatch(Meta, FunArity, Env),
  R = case D of
        {macro, {M, F, A, P}} -> {M, F, A, P};
        {function, _} -> false;
        false -> false
      end,
  {R, Env1}.

find_remote_macro(Meta, Module, FunArity, Env) ->
  Requires = ?m(Env, requires),
  Uses = ?m(Env, uses),
  %% get the original module name in case Module is a alias or rename.
  Original = case orddict:find(Module, Requires) of
               {ok, M1} -> M1;
               error -> Module
             end,
  case orddict:find(Original, Uses) of
    {ok, _} ->
      %% Original is declared in ns use clause.
      %% Load all the import macros/functions from the specified module if necessary,
      %% and then find the specified FunArity.
      {D, Env1} = find_dispatch(Meta, Original, FunArity, Env),
      R = case D of
            {macro, {M, F, A, P}} -> {M, F, A, P};
            {function, _} -> false;
            false -> false
          end,
      {R, Env1};
    error ->
      {D, Env1} = find_optional_dispatch(Meta, Original, FunArity, Env),
      R = case D of
            {macro, {M, F, A, P}} -> {M, F, A, P};
            {function, _} -> false;
            false -> false
          end,
      {R, Env1}
  end.

find_local(FunArity, #{def_fap := FAP} = Env) ->
  case filter_fa(FunArity, [FAP]) of
    [{F, A, P}] ->
      %% match current function definition
      {F, A, P};
    [] ->
      %% find in macros/functions of current namespace
      Namespace = maps:get(namespace, Env),
      Locals = kapok_symbol_table:namespace_locals(Namespace),
      case filter_fa(FunArity, Locals) of
        [{F, A, P}] -> {F, A, P};
        [] -> false
      end
  end.

find_local_function(Meta, FunArity, Env) ->
  {D, Env1} = find_dispatch(Meta, FunArity, Env),
  R = case D of
        {Tag, MFAP} when Tag == macro; Tag == function -> remote_function(MFAP);
        false -> false
      end,
  {R, Env1}.

get_remote_function(Meta, Module, FunArity, Env) ->
  {R, Env1} = find_remote_function(Meta, Module, FunArity, Env),
  R1 = case R of
         {_M, _F, _A, _P} ->
           R;
         false ->
           {F, A} = FunArity,
           remote_function(Module, F, A, 'normal')
       end,
  {R1, Env1}.

find_remote_function(Meta, Module, FunArity, Env) ->
  Requires = ?m(Env, requires),
  Uses = ?m(Env, uses),
  Module1 = case orddict:find(Module, Requires) of
              {ok, M1} -> M1;
              error -> Module
            end,
  case orddict:find(Module1, Uses) of
    {ok, _} ->
      {D, Env1} = find_dispatch(Meta, Module1, FunArity, Env),
      R = case D of
            {Tag, MFAP} when Tag == macro; Tag == function -> remote_function(MFAP);
            false -> false
          end,
      {R, Env1};
    error ->
      {D, Env1} = find_optional_dispatch(Meta, Module1, FunArity, Env),
      R = case D of
            {Tag, MFAP} when Tag == macro; Tag == function -> remote_function(MFAP);
            false -> false
          end,
      {R, Env1}
  end.

find_optional_dispatch(Meta, Module, FunArity, Env) ->
  FunImports = orddict:from_list([{Module, get_optional_functions(Module)}]),
  MacroImports = orddict:from_list([{Module, get_optional_macros(Module)}]),
  do_find_dispatch(Meta, FunArity, FunImports, MacroImports, Env).

find_dispatch(Meta, Module, FunArity, Env) ->
  Env1 = ensure_uses_imported(Env),
  %% TODO check whether module is a require alias
  FunList = case orddict:find(Module, ?m(Env1, functions)) of
                                   {ok, L1} -> L1;
                                   error -> []
          end,
  FunImports = orddict:from_list([{Module, FunList}]),
  MacroList = case orddict:find(Module, ?m(Env1, macros)) of
                {ok, L2} -> L2;
                error -> []
              end,
  MacroImports = orddict:from_list([{Module, MacroList}]),
  do_find_dispatch(Meta, FunArity, FunImports, MacroImports, Env1).

find_dispatch(Meta, FunArity, Env) ->
  Env1 = ensure_uses_imported(Env),
  do_find_dispatch(Meta, FunArity, ?m(Env1, functions), ?m(Env1, macros), Env1).

do_find_dispatch(Meta, {Fun, Arity} = FunArity, FunImports, MacroImports, Env) ->
  FunMatch = filter_import(FunArity, FunImports),
  MacroMatch = filter_import({Fun, Arity}, MacroImports),
  case {FunMatch, MacroMatch} of
    {[], [Match]} ->
      {M, [{F, A, P}]} = Match,
      {{macro, {M, F, A, P}}, Env};
    {[Match], []} ->
      {M, [{F, A, P}]} = Match,
      {{function, {M, F, A, P}}, Env};
    {[], []} ->
      {false, Env};
    _ ->
      [First, Second | _T] = FunMatch ++ MacroMatch,
      Error = {ambiguous_call, {Fun, Arity, First, Second}},
      kapok_error:form_error(Meta, ?m(Env, file), ?MODULE, Error)
  end.

filter_import(FunArity, List) when is_list(List) ->
  lists:foldl(fun({Module, Imports}, Acc) ->
                  case filter_fa(FunArity, Imports) of
                    [] -> Acc;
                    R -> orddict:store(Module, R, Acc)
                  end
              end,
              [],
              List).

filter_fa({Fun, Arity} = FunArity, FAList) when is_list(FAList) ->
  ordsets:fold(
      fun({F, A} = FA, Acc) when is_number(A) andalso FA == FunArity ->
          [{F, A, 'normal'} | Acc];
         ({Alias, {F, A, P}}, Acc) when (P == 'normal' orelse P == 'key'), {Alias, A} == FunArity ->
          [{F, A, P} | Acc];
         ({Alias, {F, A, 'rest'}}, Acc) when (Alias == Fun) andalso (A =< Arity) ->
          [{F, A, 'rest'} | Acc];
         ({F, A, P} = FAP, Acc) when (P == 'normal' orelse P == 'key'), {F, A} == FunArity ->
          [FAP | Acc];
         ({F, A, 'rest'} = FAP, Acc) when (F == Fun) andalso (A =< Arity) ->
          [FAP | Acc];
         (_, Acc) ->
          Acc
      end,
      [],
      FAList).

ensure_uses_imported(#{uses := Uses} = Env) ->
  lists:foldl(fun({Module, Args}, E) ->
                  {ok, Meta} = orddict:find(meta, Args),
                  case module_is_imported(Module, E) of
                    true -> E;
                    false -> import_module(Meta, Module, Args, E)
                  end
              end,
              Env,
              Uses).

module_is_imported(Module, #{functions := Functions, macros := Macros}) ->
  orddict:is_key(Module, Functions) orelse orddict:is_key(Module, Macros).

import_module(Meta, Module, Args, Env) ->
  {Functions, Macros} = get_exports(Meta, Module, Args, Env),
  Env1 = case Functions of
           [] -> Env;
           _ -> kapok_env:add_function(Meta, Env, Module, Functions)
         end,
  Env2 = case Macros of
           [] -> Env1;
           _ -> kapok_env:add_macro(Meta, Env1, Module, Macros)
         end,
  Env2.

get_exports(Meta, Module, Args, Env) ->
  Functions = get_functions(Meta, Module, Env),
  Macros = get_macros(Meta, Module, Env),
  {filter_exports(Functions, Args),
   filter_exports(Macros, Args)}.

ensure_loaded(Meta, Module, Env) ->
  case code:ensure_loaded(Module) of
    {module, Module} ->
      ok;
    {error, What} ->
      kapok_error:compile_error(Meta, ?m(Env, file),
                                "fail to load module: ~p due to load error: ~p", [Module, What])
  end.

get_optional_functions(Module) ->
  case code:ensure_loaded(Module) of
    {module, Module} ->
      try
        L = Module:'__info__'(functions),
        ordsets:from_list(L)
      catch
        error:undef ->
          try
            L1 = Module:module_info(exports),
            ordsets:from_list(lists:map(fun({F, A}) -> {F, A, 'normal'} end, L1))
          catch
            error:undef -> []
          end
      end;
    {error, _} -> []
  end.

get_functions(Meta, Module, Env) ->
  ensure_loaded(Meta, Module, Env),
  try
    L = Module:'__info__'(functions),
    ordsets:from_list(L)
  catch
    error:undef ->
      try
        L1 = Module:module_info(exports),
        ordsets:from_list(lists:map(fun({F, A}) -> {F, A, 'normal'} end, L1))
      catch
        error:undef ->
          kapok_error:compile_error(Meta, ?m(Env, file),
                                    "fail to get exports for unloaded module: ~p", [Module])
      end
  end.

get_optional_macros(Module) ->
  case code:ensure_loaded(Module) of
    {module, Module} ->
      try
        L = Module:'__info__'(macros),
        ordsets:from_list(L)
      catch
        error:undef -> []
      end;
    {error, _} -> []
  end.

get_macros(Meta, Module, Env) ->
  ensure_loaded(Meta, Module, Env),
  try
    L = Module:'__info__'(macros),
    ordsets:from_list(L)
 catch
   error:undef -> []
  end.

filter_exports(Exports, Args) ->
  ordsets:from_list(lists:foldl(fun filter_exports_by/2, Exports, Args)).
filter_exports_by({'only', Includes}, Exports) ->
  lists:filter(fun(FAP) ->
                   Match = lists:filter(fun(E) -> match_fa(E, FAP) end, Includes),
                   case Match of
                     [] -> false;
                     _ -> true
                   end
               end,
               Exports);
filter_exports_by({'exclude', Excludes}, Exports) ->
  lists:filter(fun(FAP)  ->
                   Match = lists:filter(fun(E) -> match_fa(E, FAP) end, Excludes),
                   case Match of
                     [] -> true;
                     _ -> false
                   end
               end,
               Exports);
filter_exports_by({'rename', Renames}, Exports) ->
  lists:foldl(fun({Fun, Arity, ParaType} = FAP, Acc) ->
                  New = lists:foldl(fun({Alias, {F, A}}, Acc0) ->
                                        case (F == Fun) andalso (A == Arity) of
                                          true -> [{Alias, {Fun, Arity, ParaType}} | Acc0];
                                          _ -> Acc0
                                        end;
                                       ({Alias, F}, Acc0) ->
                                        case (F == Fun) of
                                          true -> [{Alias, {Fun, Arity, ParaType}} | Acc0];
                                          _ -> Acc0
                                        end
                                    end,
                                    [],
                                    Renames),
                  case New of
                    [] -> [FAP | Acc];
                    _ -> New ++ Acc
                  end
              end,
              [],
              Exports);
filter_exports_by(_, Exports) ->
  Exports.

match_fa({F, A}, {Fun, Arity, _ParaType}) ->
  (F == Fun) andalso (A == Arity);
match_fa(Name, {Fun, _Arity, _ParaType}) when is_atom(Name) ->
  Name == Fun.

remote_function({Module, Name, Arity, ParaType}) ->
  remote_function(Module, Name, Arity, ParaType).
remote_function(Module, Name, Arity, ParaType) ->
  case kapok_rewrite:inline(Module, Name, Arity, ParaType) of
    {M, F, A, P} -> {M, F, A, P};
    false -> {Module, Name, Arity, ParaType}
  end.

%% ERROR HANDLING

format_error({ambiguous_call, {M, F, A, FAP1, FAP2}}) ->
  io_lib:format("find function ~ts:~ts/~B duplicates in ~p and ~p", [M, F, A, FAP1, FAP2]);
format_error({ambiguous_call, {F, A, FAP1, FAP2}}) ->
  io_lib:format("function ~ts/~B imported from both ~ts and ~ts, call in ambiguous",
                [F, A, FAP1, FAP2]).
