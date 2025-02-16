%%--------------------------------------------------------------------
%% Copyright (c) 2020-2023 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_authz_api_mnesia).

-behaviour(minirest_api).

-include_lib("emqx_auth/include/emqx_authz.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("hocon/include/hoconsc.hrl").

-import(hoconsc, [mk/1, mk/2, ref/1, ref/2, array/1, enum/1]).

-define(QUERY_USERNAME_FUN, fun ?MODULE:query_username/2).
-define(QUERY_CLIENTID_FUN, fun ?MODULE:query_clientid/2).

-define(ACL_USERNAME_QSCHEMA, [{<<"like_username">>, binary}]).
-define(ACL_CLIENTID_QSCHEMA, [{<<"like_clientid">>, binary}]).

-export([
    api_spec/0,
    paths/0,
    schema/1,
    fields/1
]).

%% operation funs
-export([
    users/2,
    clients/2,
    user/2,
    client/2,
    all/2,
    rules/2
]).

%% query funs
-export([
    query_username/2,
    query_clientid/2,
    run_fuzzy_filter/2,
    format_result/1
]).

-define(BAD_REQUEST, 'BAD_REQUEST').
-define(NOT_FOUND, 'NOT_FOUND').
-define(ALREADY_EXISTS, 'ALREADY_EXISTS').

-define(TYPE_REF, ref).
-define(TYPE_ARRAY, array).
-define(PAGE_QUERY_EXAMPLE, example_in_data).
-define(PUT_MAP_EXAMPLE, in_put_requestBody).
-define(POST_ARRAY_EXAMPLE, in_post_requestBody).

api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE, #{check_schema => true}).

paths() ->
    [
        "/authorization/sources/built_in_database/rules/users",
        "/authorization/sources/built_in_database/rules/clients",
        "/authorization/sources/built_in_database/rules/users/:username",
        "/authorization/sources/built_in_database/rules/clients/:clientid",
        "/authorization/sources/built_in_database/rules/all",
        "/authorization/sources/built_in_database/rules"
    ].

%%--------------------------------------------------------------------
%% Schema for each URI
%%--------------------------------------------------------------------

schema("/authorization/sources/built_in_database/rules/users") ->
    #{
        'operationId' => users,
        get =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(users_username_get),
                parameters =>
                    [
                        ref(emqx_dashboard_swagger, page),
                        ref(emqx_dashboard_swagger, limit),
                        {like_username,
                            mk(binary(), #{
                                in => query,
                                required => false,
                                desc => ?DESC(fuzzy_username)
                            })}
                    ],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {username_response_data, ?TYPE_REF},
                            {username, ?PAGE_QUERY_EXAMPLE}
                        )
                    }
            },
        post =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(users_username_post),
                'requestBody' => swagger_with_example(
                    {rules_for_username, ?TYPE_ARRAY},
                    {username, ?POST_ARRAY_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Created">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad username or bad rule schema">>
                        ),
                        409 => emqx_dashboard_swagger:error_codes(
                            [?ALREADY_EXISTS], <<"ALREADY_EXISTS">>
                        )
                    }
            }
    };
schema("/authorization/sources/built_in_database/rules/clients") ->
    #{
        'operationId' => clients,
        get =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(users_clientid_get),
                parameters =>
                    [
                        ref(emqx_dashboard_swagger, page),
                        ref(emqx_dashboard_swagger, limit),
                        {like_clientid,
                            mk(
                                binary(),
                                #{
                                    in => query,
                                    required => false,
                                    desc => ?DESC(fuzzy_clientid)
                                }
                            )}
                    ],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {clientid_response_data, ?TYPE_REF},
                            {clientid, ?PAGE_QUERY_EXAMPLE}
                        )
                    }
            },
        post =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(users_clientid_post),
                'requestBody' => swagger_with_example(
                    {rules_for_clientid, ?TYPE_ARRAY},
                    {clientid, ?POST_ARRAY_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Created">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad clientid or bad rule schema">>
                        )
                    }
            }
    };
schema("/authorization/sources/built_in_database/rules/users/:username") ->
    #{
        'operationId' => user,
        get =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(user_username_get),
                parameters => [ref(username)],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {rules_for_username, ?TYPE_REF},
                            {username, ?PUT_MAP_EXAMPLE}
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Not Found">>
                        )
                    }
            },
        put =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(user_username_put),
                parameters => [ref(username)],
                'requestBody' => swagger_with_example(
                    {rules_for_username, ?TYPE_REF},
                    {username, ?PUT_MAP_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad username or bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(user_username_delete),
                parameters => [ref(username)],
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad username">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Username Not Found">>
                        )
                    }
            }
    };
schema("/authorization/sources/built_in_database/rules/clients/:clientid") ->
    #{
        'operationId' => client,
        get =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(user_clientid_get),
                parameters => [ref(clientid)],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {rules_for_clientid, ?TYPE_REF},
                            {clientid, ?PUT_MAP_EXAMPLE}
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Not Found">>
                        )
                    }
            },
        put =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(user_clientid_put),
                parameters => [ref(clientid)],
                'requestBody' => swagger_with_example(
                    {rules_for_clientid, ?TYPE_REF},
                    {clientid, ?PUT_MAP_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad clientid or bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(user_clientid_delete),
                parameters => [ref(clientid)],
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad clientid">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"ClientID Not Found">>
                        )
                    }
            }
    };
schema("/authorization/sources/built_in_database/rules/all") ->
    #{
        'operationId' => all,
        get =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(rules_all_get),
                responses =>
                    #{200 => swagger_with_example({rules, ?TYPE_REF}, {all, ?PUT_MAP_EXAMPLE})}
            },
        post =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(rules_all_post),
                'requestBody' =>
                    swagger_with_example({rules, ?TYPE_REF}, {all, ?PUT_MAP_EXAMPLE}),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(rules_all_delete),
                responses =>
                    #{
                        204 => <<"Deleted">>
                    }
            }
    };
schema("/authorization/sources/built_in_database/rules") ->
    #{
        'operationId' => rules,
        delete =>
            #{
                tags => [<<"authorization">>],
                description => ?DESC(rules_delete),
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad Request">>
                        )
                    }
            }
    }.

fields(rule_item) ->
    [
        {topic,
            mk(
                string(),
                #{
                    required => true,
                    desc => ?DESC(topic),
                    example => <<"test/topic/1">>
                }
            )},
        {permission,
            mk(
                enum([allow, deny]),
                #{
                    desc => ?DESC(permission),
                    required => true,
                    example => allow
                }
            )},
        {action,
            mk(
                enum([publish, subscribe, all]),
                #{
                    desc => ?DESC(action),
                    required => true,
                    example => publish
                }
            )},
        {qos,
            mk(
                array(emqx_schema:qos()),
                #{
                    desc => ?DESC(qos),
                    default => ?DEFAULT_RULE_QOS
                }
            )},
        {retain,
            mk(
                hoconsc:union([all, boolean()]),
                #{
                    desc => ?DESC(retain),
                    default => ?DEFAULT_RULE_RETAIN
                }
            )}
    ];
fields(clientid) ->
    [
        {clientid,
            mk(
                binary(),
                #{
                    in => path,
                    required => true,
                    desc => ?DESC(clientid),
                    example => <<"client1">>
                }
            )}
    ];
fields(username) ->
    [
        {username,
            mk(
                binary(),
                #{
                    in => path,
                    required => true,
                    desc => ?DESC(username),
                    example => <<"user1">>
                }
            )}
    ];
fields(rules_for_username) ->
    fields(rules) ++
        fields(username);
fields(username_response_data) ->
    [
        {data, mk(array(ref(rules_for_username)), #{})},
        {meta, ref(emqx_dashboard_swagger, meta)}
    ];
fields(rules_for_clientid) ->
    fields(rules) ++
        fields(clientid);
fields(clientid_response_data) ->
    [
        {data, mk(array(ref(rules_for_clientid)), #{})},
        {meta, ref(emqx_dashboard_swagger, meta)}
    ];
fields(rules) ->
    [{rules, mk(array(ref(rule_item)))}].

%%--------------------------------------------------------------------
%% HTTP API
%%--------------------------------------------------------------------

users(get, #{query_string := QueryString}) ->
    case
        emqx_mgmt_api:node_query(
            node(),
            ?ACL_TABLE,
            QueryString,
            ?ACL_USERNAME_QSCHEMA,
            ?QUERY_USERNAME_FUN,
            fun ?MODULE:format_result/1
        )
    of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        {error, Node, Error} ->
            Message = list_to_binary(io_lib:format("bad rpc call ~p, Reason ~p", [Node, Error])),
            {500, #{code => <<"NODE_DOWN">>, message => Message}};
        Result ->
            {200, Result}
    end;
users(post, #{body := Body}) when is_list(Body) ->
    case ensure_all_not_exists(<<"username">>, username, Body) of
        [] ->
            lists:foreach(
                fun(#{<<"username">> := Username, <<"rules">> := Rules}) ->
                    emqx_authz_mnesia:store_rules({username, Username}, Rules)
                end,
                Body
            ),
            {204};
        Exists ->
            {409, #{
                code => <<"ALREADY_EXISTS">>,
                message => binfmt("Users '~ts' already exist", [binjoin(Exists)])
            }}
    end.

clients(get, #{query_string := QueryString}) ->
    case
        emqx_mgmt_api:node_query(
            node(),
            ?ACL_TABLE,
            QueryString,
            ?ACL_CLIENTID_QSCHEMA,
            ?QUERY_CLIENTID_FUN,
            fun ?MODULE:format_result/1
        )
    of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        {error, Node, Error} ->
            Message = list_to_binary(io_lib:format("bad rpc call ~p, Reason ~p", [Node, Error])),
            {500, #{code => <<"NODE_DOWN">>, message => Message}};
        Result ->
            {200, Result}
    end;
clients(post, #{body := Body}) when is_list(Body) ->
    case ensure_all_not_exists(<<"clientid">>, clientid, Body) of
        [] ->
            lists:foreach(
                fun(#{<<"clientid">> := ClientID, <<"rules">> := Rules}) ->
                    emqx_authz_mnesia:store_rules({clientid, ClientID}, Rules)
                end,
                Body
            ),
            {204};
        Exists ->
            {409, #{
                code => <<"ALREADY_EXISTS">>,
                message => binfmt("Clients '~ts' already exist", [binjoin(Exists)])
            }}
    end.

user(get, #{bindings := #{username := Username}}) ->
    case emqx_authz_mnesia:get_rules({username, Username}) of
        not_found ->
            {404, #{code => <<"NOT_FOUND">>, message => <<"Not Found">>}};
        {ok, Rules} ->
            {200, #{
                username => Username,
                rules => format_rules(Rules)
            }}
    end;
user(put, #{
    bindings := #{username := Username},
    body := #{<<"username">> := Username, <<"rules">> := Rules}
}) ->
    emqx_authz_mnesia:store_rules({username, Username}, Rules),
    {204};
user(delete, #{bindings := #{username := Username}}) ->
    case emqx_authz_mnesia:get_rules({username, Username}) of
        not_found ->
            {404, #{code => <<"NOT_FOUND">>, message => <<"Username Not Found">>}};
        {ok, _Rules} ->
            emqx_authz_mnesia:delete_rules({username, Username}),
            {204}
    end.

client(get, #{bindings := #{clientid := ClientID}}) ->
    case emqx_authz_mnesia:get_rules({clientid, ClientID}) of
        not_found ->
            {404, #{code => <<"NOT_FOUND">>, message => <<"Not Found">>}};
        {ok, Rules} ->
            {200, #{
                clientid => ClientID,
                rules => format_rules(Rules)
            }}
    end;
client(put, #{
    bindings := #{clientid := ClientID},
    body := #{<<"clientid">> := ClientID, <<"rules">> := Rules}
}) ->
    emqx_authz_mnesia:store_rules({clientid, ClientID}, Rules),
    {204};
client(delete, #{bindings := #{clientid := ClientID}}) ->
    case emqx_authz_mnesia:get_rules({clientid, ClientID}) of
        not_found ->
            {404, #{code => <<"NOT_FOUND">>, message => <<"ClientID Not Found">>}};
        {ok, _Rules} ->
            emqx_authz_mnesia:delete_rules({clientid, ClientID}),
            {204}
    end.

all(get, _) ->
    case emqx_authz_mnesia:get_rules(all) of
        not_found ->
            {200, #{rules => []}};
        {ok, Rules} ->
            {200, #{
                rules => format_rules(Rules)
            }}
    end;
all(post, #{body := #{<<"rules">> := Rules}}) ->
    emqx_authz_mnesia:store_rules(all, Rules),
    {204};
all(delete, _) ->
    emqx_authz_mnesia:store_rules(all, []),
    {204}.

rules(delete, _) ->
    case emqx_authz_api_sources:get_raw_source(<<"built_in_database">>) of
        [#{<<"enable">> := false}] ->
            ok = emqx_authz_mnesia:purge_rules(),
            {204};
        [#{<<"enable">> := true}] ->
            {400, #{
                code => <<"BAD_REQUEST">>,
                message =>
                    <<"'built_in_database' type source must be disabled before purge.">>
            }};
        [] ->
            {404, #{
                code => <<"BAD_REQUEST">>,
                message => <<"'built_in_database' type source is not found.">>
            }}
    end.

%%--------------------------------------------------------------------
%% QueryString to MatchSpec

-spec query_username(atom(), {list(), list()}) -> emqx_mgmt_api:match_spec_and_filter().
query_username(_Tab, {_QString, FuzzyQString}) ->
    #{
        match_spec => emqx_authz_mnesia:list_username_rules(),
        fuzzy_fun => fuzzy_filter_fun(FuzzyQString)
    }.

-spec query_clientid(atom(), {list(), list()}) -> emqx_mgmt_api:match_spec_and_filter().
query_clientid(_Tab, {_QString, FuzzyQString}) ->
    #{
        match_spec => emqx_authz_mnesia:list_clientid_rules(),
        fuzzy_fun => fuzzy_filter_fun(FuzzyQString)
    }.

%% Fuzzy username funcs
fuzzy_filter_fun([]) ->
    undefined;
fuzzy_filter_fun(Fuzzy) ->
    {fun ?MODULE:run_fuzzy_filter/2, [Fuzzy]}.

run_fuzzy_filter(_, []) ->
    true;
run_fuzzy_filter(
    E = [{username, Username}, _Rule],
    [{username, like, UsernameSubStr} | Fuzzy]
) ->
    binary:match(Username, UsernameSubStr) /= nomatch andalso run_fuzzy_filter(E, Fuzzy);
run_fuzzy_filter(
    E = [{clientid, ClientId}, _Rule],
    [{clientid, like, ClientIdSubStr} | Fuzzy]
) ->
    binary:match(ClientId, ClientIdSubStr) /= nomatch andalso run_fuzzy_filter(E, Fuzzy).

%%--------------------------------------------------------------------
%% format funcs

%% format result from mnesia tab
format_result([{username, Username}, {rules, Rules}]) ->
    #{
        username => Username,
        rules => format_rules(Rules)
    };
format_result([{clientid, ClientID}, {rules, Rules}]) ->
    #{
        clientid => ClientID,
        rules => format_rules(Rules)
    }.

format_rules(Rules) ->
    [emqx_authz_rule_raw:format_rule(Rule) || Rule <- Rules].

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

swagger_with_example({Ref, TypeP}, {_Name, _Type} = Example) ->
    emqx_dashboard_swagger:schema_with_examples(
        case TypeP of
            ?TYPE_REF -> ref(?MODULE, Ref);
            ?TYPE_ARRAY -> array(ref(?MODULE, Ref))
        end,
        rules_example(Example)
    ).

rules_example({ExampleName, ExampleType}) ->
    {Summary, Example} =
        case ExampleName of
            username -> {<<"Username">>, ?USERNAME_RULES_EXAMPLE};
            clientid -> {<<"ClientID">>, ?CLIENTID_RULES_EXAMPLE};
            all -> {<<"All">>, ?ALL_RULES_EXAMPLE}
        end,
    Value =
        case ExampleType of
            ?PAGE_QUERY_EXAMPLE ->
                #{
                    data => [Example],
                    meta => ?META_EXAMPLE
                };
            ?PUT_MAP_EXAMPLE ->
                Example;
            ?POST_ARRAY_EXAMPLE ->
                [Example]
        end,
    #{
        'password_based:built_in_database' => #{
            summary => Summary,
            value => Value
        }
    }.

ensure_all_not_exists(Key, Type, Cfgs) ->
    lists:foldl(
        fun(#{Key := Id}, Acc) ->
            case emqx_authz_mnesia:get_rules({Type, Id}) of
                not_found ->
                    Acc;
                _ ->
                    [Id | Acc]
            end
        end,
        [],
        Cfgs
    ).

binjoin([Bin]) ->
    Bin;
binjoin(Bins) ->
    binjoin(Bins, <<>>).

binjoin([H | T], Acc) ->
    binjoin(T, <<H/binary, $,, Acc/binary>>);
binjoin([], Acc) ->
    Acc.

binfmt(Fmt, Args) -> iolist_to_binary(io_lib:format(Fmt, Args)).
