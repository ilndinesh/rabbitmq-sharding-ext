-module(rabbit_sharding_test).

-include("rabbit_sharding.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

%% Used everywhere
-define(RABBIT,     {"rabbit-test",       5672}).

-import(rabbit_sharding_test_util,
        [set_param/3, clear_param/2, set_pol/3, clear_pol/1,
         plugin_dir/0, policy/1, start_other_node/1, start_other_node/2,
         start_other_node/3]).

-import(rabbit_sharding_util, [a2b/1, exchange_bin/1]).

shard_queue_creation_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "3_shard",
                        "{\"shards-per-node\": 3}"),
              set_pol("3_shard", "^sharding\\.", policy("3_shard")),
              ?assertEqual(3, length(queues("rabbit-test"))),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "3_shard"}],
                       ["3_shard"])
      end).

%% SPN = Shards Per Node
shard_update_spn_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "3_shard",
                        "{\"shards-per-node\": 3}"),
              set_pol("3_shard", "^sharding\\.", policy("3_shard")),
              ?assertEqual(3, length(queues("rabbit-test"))),

              set_param("sharding-definition", "3_shard",
                        "{\"shards-per-node\": 5}"),
              ?assertEqual(5, length(queues("rabbit-test"))),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "3_shard"}],
                       ["3_shard"])
      end).

shard_decrease_spn_keep_queues_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "5_shard",
                        "{\"shards-per-node\": 5}"),
              set_pol("5_shard", "^sharding\\.", policy("5_shard")),
              ?assertEqual(5, length(queues("rabbit-test"))),
              set_param("sharding-definition", "5_shard",
                        "{\"shards-per-node\": 3}"),
              ?assertEqual(5, length(queues("rabbit-test"))),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "5_shard"}],
                       ["5_shard"])
      end).

shard_update_spn_param_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "spn_test",
                        "{\"routing-key\": \"1234\"}"),
              set_pol("spn_test", "^sharding\\.", policy("spn_test")),

              %% by default, only ?DEFAULT_SHARDS_NUM queues should exist.
              %% only ?DEFAULT_SHARDS_NUM queues should be bound to the
              %% exchange.
              ?assertEqual(?DEFAULT_SHARDS_NUM,
                           length(queues("rabbit-test"))),
              ?assertEqual(?DEFAULT_SHARDS_NUM,
                           length(bindings("rabbit-test", <<"sharding.test">>))),

              set_param("sharding", "shards-per-node", "3"),

              ?assertEqual(3, length(queues("rabbit-test"))),
              ?assertEqual(3, length(bindings("rabbit-test", <<"sharding.test">>))),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "spn_test"},
                        {"sharding", "shards-per-node"}],
                       ["spn_test"])
      end).

shard_clear_spn_param_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "spn_test",
                        "{\"routing-key\": \"1234\"}"),
              set_param("sharding", "shards-per-node", "3"),
              set_pol("spn_test", "^sharding\\.", policy("spn_test")),
              clear_param("sharding", "shards-per-node"),

              %% queues should keep being three, but only one queue
              %% should be bound to the exchange.
              ?assertEqual(3, length(queues("rabbit-test"))),
              {ok, X} = rabbit_exchange:lookup(x(<<"sharding.test">>)),
              ?assertEqual(1, length(bindings("rabbit-test", <<"sharding.test">>))),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "spn_test"}],
                       ["spn_test"])
      end).


%% changes the routing key on the sharding defintion, therefore
%% the queues should be unbound first and then bound with the
%% new routing key.
shard_update_routing_key_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "rkey",
                        "{\"routing-key\": \"1234\"}"),
              set_pol("rkey", "^sharding\\.", policy("rkey")),
              Bs = bindings("rabbit-test", <<"sharding.test">>),

              set_param("sharding-definition", "rkey",
                        "{\"routing-key\": \"4321\"}"),
              Bs2 = bindings("rabbit-test", <<"sharding.test">>),

              ?assert(Bs =/= Bs2),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "rkey"}],
                       ["rkey"])
      end).

%% Setting the routing-key parameter should *not* affect a sharding policy
%% that provides a routing-key
shard_update_routing_key_param_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "rkey",
                        "{\"routing-key\": \"1234\"}"),
              set_pol("rkey", "^sharding\\.", policy("rkey")),
              Bs = bindings("rabbit-test", <<"sharding.test">>),

              set_param("sharding", "routing-key", "\"4321\""),
              Bs2 = bindings("rabbit-test", <<"sharding.test">>),

              ?assert(Bs =:= Bs2),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "rkey"}],
                       ["rkey"])
      end).

%% Setting the routing-key parameter *should* affect a sharding policy
%% that *doesn't* provide a routing-key
shard_update_routing_key_param_2_test() ->
    with_ch(
      fun (Ch) ->
              exchange_op(Ch, x_declare(<<"sharding.test">>)),
              set_param("sharding-definition", "rkey",
                        "{\"shards-per-node\": 3}"),
              set_pol("rkey", "^sharding\\.", policy("rkey")),
              Bs = bindings("rabbit-test", <<"sharding.test">>),

              set_param("sharding", "routing-key", "\"1234\""),
              Bs2 = bindings("rabbit-test", <<"sharding.test">>),

              ?assert(Bs =/= Bs2),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "rkey"},
                        {"sharding", "routing-key"}],
                       ["rkey"])
      end).

%% tests that the interceptor returns queue names
%% sorted by consumer count and then by queue index.
shard_basic_consume_interceptor_test() ->
    with_ch(
      fun (Ch) ->
              Sh = <<"sharding.test">>,
              exchange_op(Ch, x_declare(Sh)),
              set_param("sharding-definition", "three",
                        "{\"shards-per-node\": 3}"),
              set_pol("three", "^sharding\\.", policy("three")),

              start_consumer(Ch, Sh),
              assert_consumers(Sh, 0, 1),
              assert_consumers(Sh, 1, 0),
              assert_consumers(Sh, 2, 0),

              start_consumer(Ch, Sh),
              assert_consumers(Sh, 0, 1),
              assert_consumers(Sh, 1, 1),
              assert_consumers(Sh, 2, 0),

              start_consumer(Ch, Sh),
              assert_consumers(Sh, 0, 1),
              assert_consumers(Sh, 1, 1),
              assert_consumers(Sh, 2, 1),

              start_consumer(Ch, Sh),
              assert_consumers(Sh, 0, 2),
              assert_consumers(Sh, 1, 1),
              assert_consumers(Sh, 2, 1),

              teardown(Ch,
                       [<<"sharding.test">>],
                       [{"sharding-definition", "three"}],
                       ["three"])
      end).

start_consumer(Ch, Shard) ->
    amqp_channel:call(Ch, #'basic.consume'{queue = Shard}).

assert_consumers(Shard, QInd, Count) ->
    Q0 = q(shard_q(x(Shard), QInd)),
    [{consumers, C0}] = rabbit_sharding_interceptor:consumer_count(Q0),
    ?assertEqual(C0, Count).

queues(Nodename) ->
    case rpc:call(n(Nodename), rabbit_amqqueue, list, [<<"/">>]) of
        {badrpc, _} -> [];
        Qs          -> Qs
    end.

bindings(Nodename, XName) ->
    case rpc:call(n(Nodename), rabbit_binding, list_for_source, [x(XName)]) of
        {badrpc, _} -> [];
        Bs          -> Bs
    end.

with_ch(Fun) ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    Fun(Ch),
    amqp_connection:close(Conn),
    cleanup(?RABBIT),
    ok.

cleanup({Nodename, _}) ->
    [rpc:call(n(Nodename), rabbit_amqqueue, delete, [Q, false, false]) ||
        Q <- queues(Nodename)].

teardown(Ch, Xs, Params, Policies) ->
    [exchange_op(Ch, x_delete(XName)) || XName <- Xs],
    [clear_param(Comp, Param) || {Comp, Param} <- Params],
    [clear_pol(Policy) || Policy <- Policies].

exchange_op(Ch, Op) ->
    amqp_channel:call(Ch, Op).

x_declare(Name) -> x_declare(Name, <<"x-consistent-hash">>).

x_declare(Name, Type) ->
    #'exchange.declare'{exchange = Name,
                        type     = Type,
                        durable  = true}.

x_delete(Name) ->
    #'exchange.delete'{exchange = Name}.

x(Name) -> rabbit_misc:r(<<"/">>, exchange, Name).
q(Name) -> rabbit_misc:r(<<"/">>, queue, Name).

shard_q(X, N) ->
    rabbit_sharding_util:make_queue_name(
      exchange_bin(X), a2b(node()), N).

n(Nodename) ->
    {_, NodeHost} = rabbit_nodes:parts(node()),
    rabbit_nodes:make({Nodename, NodeHost}).