%%%-------------------------------------------------------------------
%%% @author xuchaoqian
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. Jun 2018 5:35 PM
%%%-------------------------------------------------------------------
-module(maxwell_backend_puller).
-behaviour(gen_server).

-include_lib("maxwell_protocol/include/maxwell_protocol_pb.hrl").
-include_lib("maxwell_store/include/maxwell_store.hrl").

%% API
-export([
  start_link/3,
  ensure_started/3,
  pull/2
]).

%% gen_server callbacks
-export([
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3
]).

-define(PROCESS_NAME(Topic, HandlerPid, PullerId), {puller, Topic, HandlerPid}).
-define(VIA_PROCESS_NAME(Topic, HandlerPid, PullerId),
  {via, maxwell_server_registry, ?PROCESS_NAME(Topic, HandlerPid, PullerId)}
).

-record(state, {
  topic,
  store_ref,
  store_pid,
  handler_ref,
  handler_pid,
  puller_id,
  pending_pull_req
}).

%%%===================================================================
%%% API
%%%===================================================================
start_link(Topic, HandlerPid, PullerId) ->
  gen_server:start_link(
    ?VIA_PROCESS_NAME(Topic, HandlerPid, PullerId),
    ?MODULE, [Topic, HandlerPid, PullerId], []
  ).

ensure_started(Topic, HandlerPid, PullerId) ->
  case maxwell_server_registry:whereis_name(
    ?PROCESS_NAME(Topic, HandlerPid, PullerId)
  ) of
    undefined ->
      case maxwell_server_puller_sup:start_child(
        Topic, HandlerPid, PullerId
      ) of
        {error, {already_started, Pid}} -> {ok, Pid};
        {ok, _} = Result -> Result
      end;
    Pid -> {ok, Pid}
  end.

pull(Pid, Msg) ->
  gen_server:cast(Pid, {pull, Msg}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([Topic, HandlerPid, PullerId]) ->
  State = init_state(Topic, HandlerPid, PullerId),
  lager:info("Initializing ~p: state: ~p", [?MODULE, State]),
  {ok, State}.

handle_call(Request, _From, State) ->
  lager:error("Received unknkonw call: ~p", [Request]),
  reply({ok, State}).

handle_cast({pull, Msg}, State) ->
  noreply(pull0(Msg, State));
handle_cast(Request, State) ->
  lager:error("Received unknkonw cast: ~p", [Request]),
  noreply(State).

handle_info(?MAXWELL_STORE_NOTIFY_CMD(Topic, MaxOffset), State) ->
  lager:debug("~p", [?MAXWELL_STORE_NOTIFY_CMD(Topic, MaxOffset)]),
  noreply(notify(State));
handle_info({'DOWN', StoreRef, process, _StorePid, Reason},
    #state{store_ref = StoreRef} = State) ->
  lager:info(
    "Store was down: state: ~p, reason: ~p", [State, Reason]
  ),
  noreply(init_store(State));
handle_info({'DOWN', HandlerRef, process, _HandlerPid, Reason},
    #state{handler_ref = HandlerRef} = State) ->
  lager:info(
    "Handler was down: state: ~p, reason: ~p", [State, Reason]
  ),
  stop({{error, handler_down}, State});
handle_info(Info, State) ->
  lager:error("Received unknkonw info: ~p", [Info]),
  noreply(State).

terminate(Reason, State) ->
  lager:info(
    "Terminating ~p: state: ~p, reason: ~p",
    [?MODULE, State, Reason]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

init_state(Topic, HandlerPid, PullerId) ->
  State = #state{
    topic = Topic,
    handler_pid = HandlerPid,
    puller_id = PullerId,
    pending_pull_req = undefined
  },
  monitor_handler(init_store(State)).

init_store(State) ->
  {StoreRef, StorePid} = get_store(State#state.topic),
  maxwell_store_topic_owner:add_watcher(StorePid, self()),
  State#state{store_ref = StoreRef, store_pid = StorePid}.

get_store(Topic) ->
  {ok, Pid} = maxwell_store_topic_owner:ensure_started(Topic),
  Ref = erlang:monitor(process, Pid),
  {Ref, Pid}.

monitor_handler(State) ->
  Ref = erlang:monitor(process, State#state.handler_pid),
  State#state{handler_ref = Ref}.

pull0(#pull_req_t{
  offset = Offset, limit = Limit, ref = Ref
} = PullReq, State) ->
  Entries = maxwell_store_topic_owner:get_from(
    State#state.store_pid, Offset, Limit
  ),
  case erlang:length(Entries) > 0 of
    true ->
      Rep = #pull_rep_t{msgs = build_msgs(Entries), ref = Ref},
      maxwell_server_handler:send(State#state.handler_pid, Rep),
      State#state{pending_pull_req = undefined};
    false ->
      State#state{pending_pull_req = PullReq}
  end.

build_msgs(Entries) ->
  lists:reverse(lists:foldl(
    fun({Offset, Value, Timestamp}, Msgs) ->
      Msg = #msg_t{
        offset = Offset, value = Value, timestamp = Timestamp
      },
      [Msg | Msgs]
    end, [], Entries)
  ).

notify(State) ->
  case State#state.pending_pull_req of
    undefined -> State;
    PullReq -> pull0(PullReq, State)
  end.

reply({Reply, State}) ->
  {reply, Reply, State}.

noreply(State) ->
  {noreply, State}.

stop({Reason, State}) ->
  {stop, Reason, State}.