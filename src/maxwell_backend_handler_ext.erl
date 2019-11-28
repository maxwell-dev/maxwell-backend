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

-record(state, {
  key_pushers,
  pusher_keys,
  key_pullers,
  puller_keys
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
    key_pullers = dict:new(), 
    puller_keys = dict:new(), 
    key_pushers = dict:new(),
    pusher_keys = dict:new()
  }.

handle2(#push_req_t{topic = Topic} = Req , State) ->
  {PusherPid, State2} = ensure_pusher_started(Topic, State),
  maxwell_backend_pusher:push(PusherPid, Req),
  noreply(State2);

handle2(#push_rep_t{} = Rep , State) ->
  reply(Rep, State);

handle2(#pull_req_t{topic = Topic, puller = PullerId} = Req, State) ->
  {PullerPid, State2} = ensure_puller_started(Topic, PullerId, State),
  maxwell_backend_puller:pull(PullerPid, Req),
  noreply(State2);

handle2(#pull_rep_t{} = Rep , State) ->
  reply(Rep, State);

handle2({'DOWN', Ref, process, _Pid, Reason}, State) ->
  lager:info("Pusher or Puller was down: state: ~p, reason: ~p", [State, Reason]),
  noreply(erase_puller_by_ref(Ref, erase_pusher_by_ref(Ref, State))).

ensure_pusher_started(Topic, State) ->
  case dict:find(Topic, State#state.key_pushers) of
    {ok, {_, PusherPid}} -> {PusherPid, State};
    error -> start_pusher(Topic, State)
  end.

start_pusher(Topic, State) ->
  {ok, Pid} = maxwell_backend_pusher_sup:start_child(Topic, self()),
  Ref = erlang:monitor(process, Pid),
  KeyPushers = dict:store(Topic, {Ref, Pid}, State#state.key_pushers),
  PusherKeys = dict:store(Ref, Topic, State#state.pusher_keys),
  {Pid, State#state{key_pushers = KeyPushers, pusher_keys = PusherKeys}}.

erase_pusher_by_ref(Ref, State) ->
  case dict:find(Ref, State#state.pusher_keys) of
    {ok, Topic} -> 
      PusherKeys = dict:erase(Ref, State#state.pusher_keys),
      KeyPushers = dict:erase(Topic, State#state.key_pushers),
      State#state{key_pushers = KeyPushers, pusher_keys = PusherKeys};
    error -> State
  end.

ensure_puller_started(Topic, PullerId, State) ->
  case dict:find({Topic, PullerId}, State#state.key_pullers) of
    {ok, {_, PullerPid}} -> {PullerPid, State};
    error -> start_puller(Topic, PullerId, State)
  end.

start_puller(Topic, PullerId, State) ->
  {ok, Pid} = maxwell_backend_puller_sup:start_child(Topic, self(), PullerId),
  Ref = erlang:monitor(process, Pid),
  Key = {Topic, PullerId},
  KeyPullers = dict:store(Key, {Ref, Pid}, State#state.key_pullers),
  PullerKeys = dict:store(Ref, Key, State#state.puller_keys),
  {Pid, State#state{key_pullers = KeyPullers, puller_keys = PullerKeys}}.

erase_puller_by_ref(Ref, State) ->
  case dict:find(Ref, State#state.puller_keys) of
    {ok, Key} -> 
      PullerKeys = dict:erase(Ref, State#state.puller_keys),
      KeyPullers = dict:erase(Key, State#state.key_pullers),
      State#state{key_pullers = KeyPullers, puller_keys = PullerKeys};
    error -> State
  end.

reply(Reply, State) ->
  {reply, Reply, State}.

noreply(State) ->
  {noreply, State}.