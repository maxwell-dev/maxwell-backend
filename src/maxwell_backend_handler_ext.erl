%%%-------------------------------------------------------------------
%%% @author xuchaoqian
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. Jun 2018 5:35 PM
%%%-------------------------------------------------------------------
-module(maxwell_backend_handler_ext).

-include_lib("maxwell_protocol/include/maxwell_protocol_pb.hrl").
-include_lib("maxwell_store/include/maxwell_store.hrl").

-export([
  init/1,
  handle/2,
  terminate/2
]).

-define(SEND_CMD(Msg), {'$send', Msg}).

-record(state, {
  topic_stores,
  store_topics,
  pending_pull_reqs
}).

%%%===================================================================
%%% Server callbacks
%%%===================================================================
init(_Req) ->
  init_state().

handle(Msg, State) ->
  handle2(Msg, State).

terminate(_Reason, _State) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
init_state() ->
  #state{
    topic_stores = dict:new(), 
    store_topics = dict:new(), 
    pending_pull_reqs = dict:new()
  }.

handle2(#push_req_t{topic = Topic, value = Value, ref = Ref}, State) ->
  {StorePid, State2} = ensure_store_started(Topic, State),
  ok = maxwell_store_topic_owner:put_values(StorePid, [Value]),
  reply(#push_rep_t{ref = Ref}, State2);

handle2(#pull_req_t{
  topic = Topic, offset = Offset, limit = Limit, ref = Ref
} = PullReq, State) ->
  {StorePid, State2} = ensure_store_started(Topic, State),
  Entries = maxwell_store_topic_owner:get_from(StorePid, Offset, Limit),
  case erlang:length(Entries) > 0 of
    true ->
      send(#pull_rep_t{msgs = build_msgs(Entries), ref = Ref}),
      noreply(State2#state{
        pending_pull_reqs = dict:store(
          Topic, undefined, State2#state.pending_pull_reqs
        )
      });
    false ->
      noreply(State2#state{
        pending_pull_reqs = dict:store(
          Topic, PullReq, State2#state.pending_pull_reqs
        )
      })
  end;

handle2(?MAXWELL_STORE_NOTIFY_CMD(Topic, MaxOffset), State) ->
  lager:debug("~p", [?MAXWELL_STORE_NOTIFY_CMD(Topic, MaxOffset)]),
  noreply(notify(Topic, State));

handle2({'DOWN', StoreRef, process, _StorePid, Reason}, State) ->
  lager:info(
    "Store was down: state: ~p, reason: ~p", [State, Reason]
  ),
  noreply(erase_store_by_ref(StoreRef, State)).

ensure_store_started(Topic, State) ->
  case dict:find(Topic, State#state.topic_stores) of
    {ok, {_, StorePid}} -> {StorePid, State};
    error -> start_store(Topic, State)
  end.

start_store(Topic, State) ->
  {ok, Pid} = maxwell_store_topic_owner:ensure_started(Topic),
  Ref = erlang:monitor(process, Pid),
  TopicStores = dict:store(Topic, {Ref, Pid}, State#state.topic_stores),
  StoreTopics = dict:store(Ref, Topic, State#state.store_topics),
  {Pid, State#state{topic_stores = TopicStores, store_topics = StoreTopics}}.

erase_store_by_ref(Ref, State) ->
  case dict:find(Ref, State#state.store_topics) of
    {ok, Topic} -> 
      StoreTopics = dict:erase(Ref, State#state.store_topics),
      TopicStores = dict:erase(Topic, State#state.topic_stores),
      State#state{topic_stores = TopicStores, store_topics = StoreTopics};
    error -> State
  end.

build_msgs(Entries) ->
  lists:reverse(lists:foldl(
    fun({Offset, Value, Timestamp}, Msgs) ->
      Msg = #msg_t{offset = Offset, value = Value, timestamp = Timestamp},
      [Msg | Msgs]
    end, [], Entries
  )).

notify(Topic, State) ->
  case dict:find(Topic, State#state.pending_pull_reqs) of
    {ok, PullReq} -> handle2(PullReq, State);
    error -> State
  end.

reply(Reply, State) ->
  {reply, Reply, State}.

noreply(State) ->
  {noreply, State}.

send(Msg) ->
  self() ! ?SEND_CMD(Msg).