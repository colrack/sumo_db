%%% @doc MongoDB repository implementation.
%%%
%%% Copyright 2012 Inaka &lt;hello@inaka.net&gt;
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @end
%%% @copyright Inaka <hello@inaka.net>
%%%
-module(sumo_repo_elasticsearch).
-author("Juan Facorro <juan@inaka.com>").
-github("https://github.com/inaka").
-license("Apache License 2.0").

-behavior(sumo_repo).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([
         init/1, create_schema/2, persist/2, find_by/3, find_by/5,
         delete/3, delete_by/3, delete_all/2
        ]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {index:: string()}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% External API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init(Options) ->
    %% ElasticSearch client uses poolboy to handle its own pool of workers
    %% so no pool is required.
    Backend = proplists:get_value(storage_backend, Options),
    Index = sumo_backend_elasticsearch:get_index(Backend),
    {ok, #state{index = Index}}.

persist(Doc, #state{index = Index} = State) ->
    DocName = sumo_internal:doc_name(Doc),
    IdField = sumo_internal:id_field_name(DocName),
    Id =  sumo_internal:get_field(IdField, Doc),
    Fields = sumo_internal:doc_fields(Doc),
    {ok, _} = elasticsearch:index(Index, atom_to_list(DocName), Id, Fields),

    {ok, Doc, State}.

delete(DocName, Id, State) ->
    delete_by(DocName, [{id, Id}], State).

delete_by(DocName, Conditions, State) ->
    Args = [?MODULE, DocName, Conditions, State],
    lager:critical("Unimplemented function: ~p:delete_by(~p, ~p, ~p)", Args),
    {error, not_implemented, State}.

delete_all(DocName, #state{index = Index} = State) ->
    lager:debug("dropping type: ~p", [DocName]),
    {ok, _} = elasticsearch:delete(Index, DocName, <<"">>),
    {ok, unknown, State}.

find_by(DocName, _Conditions, _Limit, _Offset,
        #state{index = Index} = State) ->
    Query = [{query, [{ match , [{'_all', <<"joni">>}] }]}],
    io:format("~p~n", [jsx:encode(Query)]),
    {ok, Docs} = elasticsearch:search(Index, atom_to_list(DocName), Query),
    Hits = proplists:get_value(<<"hits">>, Docs),
    Hits1 = proplists:get_value(<<"hits">>, Hits),
    io:format("==== ~p~n", [Hits1]),
    {ok, Hits1, State}.

find_by(DocName, Conditions, State) ->
    find_by(DocName, Conditions, 0, 0, State).

create_schema(Schema, #state{index = Index} = State) ->
    SchemaName = sumo_internal:schema_name(Schema),
    Fields = sumo_internal:schema_fields(Schema),
    Fun = fun(Field, Acc) ->
                  _Name = sumo_internal:field_name(Field),
                  _Attrs = sumo_internal:field_attrs(Field),
                  Acc
          end,
    Mappings = lists:foldl(Fun, #{}, Fields),
    lager:debug("creating type: ~p", [SchemaName]),
    elasticsearch:create_index(Index, [], Mappings),
    {ok, State}.

%% [{id,<<"1">>}, {id,undefined}, {title,"Title"}, {content,"Some content"}, {author_id,1}]
