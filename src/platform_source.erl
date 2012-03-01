%% @copyright 2012 defpage.com
%% @doc Synchronize documents in metadata server with sources.

-module(platform_source).
-export([sync/1]).
-export([get_meta/1, get_sources/2]).

-include("platform.hrl").

-type(source_type() :: gd | undefined).

-record(meta_doc, {meta_id :: string(),
		   source_type :: string(),
		   title :: string(),
		   modified :: string()}).

-record(source_doc, {title :: string(),
		     modified :: string()}).

-spec(sync(Id::integer()) -> term()).
%% @doc Run sync process.
sync(CollectionId) ->
    {SourceType, MetaDocs} = get_meta(CollectionId),
    SourceDocs = get_sources(SourceType, CollectionId),
    lists:foreach(get_fun_update(SourceType, CollectionId, MetaDocs), SourceDocs),
    ok.

-spec(get_meta(CollectionId::integer()) -> {source_type(), [#meta_doc{}]}).
%% Get metadata info.
get_meta(CollectionId) ->
    Url = ?META_URL ++ "/collections/" ++ integer_to_list(CollectionId),
    case httpc:request(get, {Url, [?META_AUTH]}, [], []) of
	{ok, {{_, 200, _}, _, Body}} ->
	    {struct, Fields} = mochijson2:decode(Body),
	    Docs = proplists:get_value(<<"documents">>, Fields),
	    {source_type(Fields), [meta_doc(X) || X <- Docs]};
	{ok, {{_, 404, _}, _, _}} ->
	    error;
	_ ->
	    error
    end.

-spec(source_type(Fields::[tuple()]) -> source_type()).
%% Extract source type for collection. Assume alone.
source_type(Fields) ->
    [{struct, Source} | _] = proplists:get_value(<<"sources">>, Fields),
    case proplists:get_value(<<"type">>, Source) of
	<<"gd">> -> gd;
	_ -> error
    end.

-spec(get_sources(source_type(), CollectionId::integer()) -> [#source_doc{}]).
%% Get list of info about source documents.
get_sources(gd, CollectionId) ->
    Url = ?GD_URL ++ "/api/collection/" ++ integer_to_list(CollectionId) ++ "/documents",
    case httpc:request(Url) of
	{ok, {{_, 200, _}, _, Body}} ->
	    [source_doc(X) || X <- mochijson2:decode(Body)];
	{ok, {{_, 404, _}, _, _}} ->
	    error;
	_ ->
	    error
    end.

%% Create property with record #meta_doc{} from json structure
meta_doc({struct, Fields}) ->
    {struct, Source} = mochijson2:decode(proplists:get_value(<<"source">>, Fields)), % ?!!
    {proplists:get_value(<<"id">>, Source),
     #meta_doc{meta_id = proplists:get_value(<<"id">>, Fields),
	       source_type = proplists:get_value(<<"type">>, Source),
	       title = proplists:get_value(<<"title">>, Fields),
	       modified = rfc3339:parse_epoch(
			    binary_to_list(
			      proplists:get_value(<<"modified">>, Fields)))}}.

%% Create property with record #source_doc{} from json structure
source_doc({struct, Fields}) ->
    {proplists:get_value(<<"id">>, Fields),
     #source_doc{title = proplists:get_value(<<"title">>, Fields),
		 modified = rfc3339:parse_epoch(
			      binary_to_list(
				proplists:get_value(<<"modified">>, Fields)))}}.

-spec(get_fun_update(SourceType::atom(),
		     CollectionId::integer(),
		     MetaDocs::list()) -> function()).
%% Return function which update meta docs if need, for given source document.
get_fun_update(SourceType, CollectionId, MetaDocs) ->
    fun({SourceId, SourceDoc}) ->
	    case proplists:get_value(SourceId, MetaDocs) of
		undefined ->
		    Source = {struct, [{<<"type">>, list_to_binary(atom_to_list(SourceType))},
				       {<<"id">>, SourceId}]},
		    Fields = {struct, [{<<"title">>, SourceDoc#source_doc.title},
				       {<<"source">>, Source},
				       {<<"collection_id">>, CollectionId}]},
		    Request = {?META_URL ++ "/documents/",
			       [?META_AUTH],
			       "application/json",
			       iolist_to_binary(mochijson2:encode(Fields))},
		    case httpc:request(post, Request, [], []) of
			{ok, {{_, 201, _}, _, Body}} ->
			    {struct, ResponseFields} = mochijson2:decode(Body),
			    _DocId = proplists:get_value(<<"id">>, ResponseFields),
			    ok;
			_ ->
			    ok
		    end;
		{meta_doc, _MMetaId, _SourceType, MTitle, _MModified} ->
		    io:format("QQQQQQQQQQQQQ -- ~p -- QQQQQQQQQQQ", [MTitle])
	    end
    end.
