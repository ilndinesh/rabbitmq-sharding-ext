-module(rabbit_sharding_ext_util).

-export([shard/1, sharded_exchanges/1]).
-export([get_policy/2, shards_per_node/1, routing_key/1]).
-export([exchange_bin/1, make_queue_name/3, a2b/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

-import(rabbit_misc, [pget/3]).

shard(X) ->
    case get_policy(<<"shards-per-node">>, X) of
        undefined -> false;
        _SPN      -> true
    end.

sharded_exchanges(VHost) ->
    [X || X <- rabbit_exchange:list(VHost), shard(X)].

shards_per_node(X) ->
    get_policy(<<"shards-per-node">>, X).

routing_key(X) ->
    get_policy(<<"routing-key">>, X).

get_policy(Key, X) ->
    rabbit_policy:get(Key, X).

exchange_bin(#resource{name = XBin}) -> XBin.

make_queue_name(QBin, NodeBin, QNum) ->
    %% we do this to prevent unprintable characters in queue names
    QNumBin = list_to_binary(lists:flatten(io_lib:format("~p", [QNum]))),
    <<"sharding: ", QBin/binary, " - ", NodeBin/binary, " - ", QNumBin/binary>>.

a2b(A) -> list_to_binary(atom_to_list(A)).
