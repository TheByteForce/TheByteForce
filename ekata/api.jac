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
"""

import from ekata.views {
    MsgView,
    QueueRow,
    IncidentView,
    TraceRow,
    ReplayStep,
    Metrics,
    DemoState
}
import from ekata.store {
    get_hub,
    next_msg_id,
    find_incident,
    find_message,
    incident_of,
    is_seeded
}
import from ekata.seed { reset_and_seed }
import from ekata.locking { graph_writer }
import from ekata.store { all_messages, all_incidents, open_pending, has_call_log, log_decision, to_int }
import from ekata.referee { r5_claim }
import from ekata.schema { RefereeOutcome }
import from ekata.fixtures { prepare_replay, load_fixture }
import from ekata.coordinator {
    process_message,
    replay_in_hub,
    build_queue,
    build_incident_view,
    decisions_since,
    apply_merge_decision,
    record_call,
    build_metrics,
    msg_view
}

def:pub load_demo() -> DemoState {
    with graph_writer() {
        hub = get_hub();
        reset_and_seed(hub);
        total = prepare_replay(hub);
        commit();
        return DemoState(
            seeded=True, position=0, total=total, storm_time=hub.storm_time, synthetic=True
        );
    }
}

def:pub demo_state(tick: int = 0) -> DemoState {
    hub = get_hub();
    total = hub.replay_total;
    if total == 0 {
        total = len(load_fixture());
    }
    return DemoState(
        seeded=is_seeded(hub),
        position=hub.replay_pos,
        total=total,
        storm_time=hub.storm_time,
        synthetic=True
    );
}

def:pub replay_next(steps: int = 1) -> ReplayStep {
    with graph_writer() {
        return replay_in_hub(get_hub(), steps);
    }
}

def:pub submit_message(text: str, channel: str = "WEB") -> ReplayStep {
    with graph_writer() {
        if text.strip() == "" { raise ValueError("Enter a message first."); }
        hub = get_hub();
        before = hub.decision_seq;
        msg = process_message(text, channel, hub.storm_time, next_msg_id(hub));
        return ReplayStep(
            done=hub.replay_total > 0 and hub.replay_pos >= hub.replay_total,
            locked=hub.replay_lock,
            position=hub.replay_pos,
            total=hub.replay_total,
            storm_time=hub.storm_time,
            message=msg_view(msg),
            queue=build_queue(hub),
            new_trace=decisions_since(hub, before, 400)
        );
    }
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

def:pub decide_merge(
    msg_id: str, inc_id: str, approve: bool, desk: str
) -> IncidentView | None {
    with graph_writer() {
        hub = get_hub();
        inc = apply_merge_decision(hub, msg_id, inc_id, approve, desk);
        commit();
        if inc is None {
            return None;
        }
        return build_incident_view(hub, inc);
    }
}

def:pub log_call(
    inc_id: str, outcome: str, desk: str, note: str = ""
) -> IncidentView | None {
    with graph_writer() {
        hub = get_hub();
        current = find_incident(hub, inc_id);
        if current is not None and r5_claim(current.claimed_by, desk).outcome == RefereeOutcome.BLOCKED { raise ValueError("This incident is claimed by another desk."); }
        inc = record_call(hub, inc_id, outcome, desk, note);
        commit();
        if inc is None {
            return None;
        }
        return build_incident_view(hub, inc);
    }
}

def:pub trace_since(cursor: int = 0) -> list[TraceRow] {
    return decisions_since(get_hub(), cursor, 50);
}

def:pub metrics(tick: int = 0) -> Metrics {
    return build_metrics(get_hub());
}


def:pub recent_messages(tick: int = 0) -> list[MsgView] {
    return [msg_view(m) for m in sorted(all_messages(get_hub()), key=lambda (m) { m.seq; }, reverse=True)[:300]];
}

def:pub claim_incident(inc_id: str, desk: str, release: bool = False) -> IncidentView | None {
    with graph_writer() {
        hub = get_hub();
        inc = find_incident(hub, inc_id);
        if inc is None { return None; }
        if desk.strip() == "" { raise ValueError("Choose a desk."); }
        if r5_claim(inc.claimed_by, desk).outcome == RefereeOutcome.BLOCKED { raise ValueError("Already claimed by another desk."); }
        inc.claimed_by = "" if release else desk;
        if inc.status == "NEW" and not release { inc.status = "VERIFYING"; }
        if inc.status == "VERIFYING" and release { inc.status = "NEW"; }
        log_decision(hub, "desk", "release" if release else "claim", desk + " updated its claim", "APPLIED", hub.storm_time, [inc], model="human", target_label=inc_id);
        commit();
        return build_incident_view(hub, inc);
    }
}

def:pub resolve_change(inc_id: str, field: str, desk: str, accept: bool) -> IncidentView | None {
    with graph_writer() {
        hub = get_hub();
        inc = find_incident(hub, inc_id);
        if inc is None { return None; }
        if not has_call_log(inc) or inc.claimed_by != desk { raise ValueError("Log a verification call as the claiming desk first."); }
        for p in open_pending(hub, inc_id) {
            if p.fld == field {
                if accept and field == "headcount" { inc.headcount = to_int(p.new_value); }
                if accept and field == "place" { inc.place = p.new_value; }
                p.status = "ACCEPTED" if accept else "REJECTED";
            }
        }
        log_decision(hub, "desk", "resolve_contradiction", desk + " reviewed " + field, "APPLIED", hub.storm_time, [inc], model="human", target_label=inc_id);
        commit();
        return build_incident_view(hub, inc);
    }
}
