"""Public endpoints for the Ekata desk (all :pub, all anchored on root.shared).

Signatures are the contract between the backend and the UI. Bodies are
placeholders until the backend implementation replaces them.
Readers take a tick/cursor argument because the client caches reads for 60 s.
"""

import from ekata.views {
    MsgView, QueueRow, IncidentView, TraceRow, ReplayStep, Metrics, DemoState
}

def:pub load_demo() -> DemoState {
    return DemoState(seeded=False);
}

def:pub demo_state(tick: int = 0) -> DemoState {
    return DemoState();
}

def:pub replay_next(steps: int = 1) -> ReplayStep {
    return ReplayStep(done=True);
}

def:pub submit_message(text: str, channel: str = "WEB") -> ReplayStep {
    return ReplayStep();
}

def:pub call_queue(tick: int = 0) -> list[QueueRow] {
    return [];
}

def:pub incident_detail(inc_id: str, tick: int = 0) -> IncidentView | None {
    return None;
}

def:pub decide_merge(msg_id: str, inc_id: str, approve: bool, desk: str) -> IncidentView | None {
    return None;
}

def:pub log_call(inc_id: str, outcome: str, desk: str, note: str = "") -> IncidentView | None {
    return None;
}

def:pub trace_since(cursor: int = 0) -> list[TraceRow] {
    return [];
}

def:pub metrics(tick: int = 0) -> Metrics {
    return Metrics();
}
