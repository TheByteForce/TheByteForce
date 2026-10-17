"""Public endpoints for the Ekata desk (all :pub, all anchored on root.shared).

Signatures are the contract between the backend and the UI. The bodies are
thin: the work happens in coordinator.jac on the hub from get_hub().
Readers take a tick/cursor argument because the client caches reads for 60 s.

Report shapes (the typed return value is the wire format, see views.jac):
  load_demo / demo_state -> DemoState
  replay_next / submit_message -> ReplayStep (message just processed, current
      call queue, the Decisions created by this call)
  call_queue -> list[QueueRow] (open incidents, highest priority first)
  incident_detail / decide_merge / log_call -> IncidentView | None
  trace_since -> list[TraceRow] (ascending, at most 50)
  metrics -> Metrics
  inbox_messages -> list[MsgView] (messages received so far, newest first)
"""

import from ekata.views {
    MsgView, QueueRow, IncidentView, TraceRow, ReplayStep, Metrics, DemoState
}
import from ekata.store {
    get_hub, next_msg_id, find_incident, find_message, incident_of, is_seeded, all_messages
}
import from ekata.schema { Message }
import from ekata.seed { reset_and_seed }
import from ekata.fixtures { prepare_replay, load_fixture }
import from ekata.coordinator {
    process_message, replay_in_hub, build_queue, build_incident_view, decisions_since,
    apply_merge_decision, record_call, build_metrics, msg_view
}

def:pub load_demo() -> DemoState {
    hub = get_hub();
    reset_and_seed(hub);
    total = prepare_replay(hub);
    commit();
    return DemoState(seeded=True, position=0, total=total, storm_time=hub.storm_time, synthetic=True);
}

def:pub demo_state(tick: int = 0) -> DemoState {
    hub = get_hub();
    total = hub.replay_total;
    if total == 0 {
        total = len(load_fixture());
    }
    return DemoState(
        seeded=is_seeded(hub), position=hub.replay_pos, total=total,
        storm_time=hub.storm_time, synthetic=True
    );
}

def:pub replay_next(steps: int = 1) -> ReplayStep {
    return replay_in_hub(get_hub(), steps);
}

def:pub submit_message(text: str, channel: str = "WEB") -> ReplayStep {
    hub = get_hub();
    before = hub.decision_seq;
    msg = process_message(text, channel, hub.storm_time, next_msg_id(hub));
    return ReplayStep(
        done=hub.replay_total > 0 and hub.replay_pos >= hub.replay_total,
        locked=hub.replay_lock, position=hub.replay_pos, total=hub.replay_total,
        storm_time=hub.storm_time, message=msg_view(msg),
        queue=build_queue(hub), new_trace=decisions_since(hub, before, 400)
    );
}

def:pub call_queue(tick: int = 0) -> list[QueueRow] {
    return build_queue(get_hub());
}

def:pub incident_detail(inc_id: str, tick: int = 0) -> IncidentView | None {
    hub = get_hub();
    inc = find_incident(hub, inc_id);
    if inc is None {
        return None;
    }
    return build_incident_view(hub, inc);
}

def:pub decide_merge(msg_id: str, inc_id: str, approve: bool, desk: str) -> IncidentView | None {
    hub = get_hub();
    inc = apply_merge_decision(hub, msg_id, inc_id, approve, desk);
    commit();
    if inc is None {
        return None;
    }
    return build_incident_view(hub, inc);
}

def:pub log_call(inc_id: str, outcome: str, desk: str, note: str = "") -> IncidentView | None {
    hub = get_hub();
    inc = record_call(hub, inc_id, outcome, desk, note);
    commit();
    if inc is None {
        return None;
    }
    return build_incident_view(hub, inc);
}

def:pub trace_since(cursor: int = 0, tick: int = 0) -> list[TraceRow] {
    return decisions_since(get_hub(), cursor, 50);
}

def:pub metrics(tick: int = 0) -> Metrics {
    return build_metrics(get_hub());
}

def message_seq(m: Message) -> int {
    return m.seq;
}

def:pub inbox_messages(tick: int = 0) -> list[MsgView] {
    msgs = sorted(all_messages(get_hub()), key=message_seq, reverse=True);
    return [msg_view(m) for m in msgs];
}
