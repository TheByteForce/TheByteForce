"""A bounded top-five explainer; deterministic vulnerability floors always win."""
import os;
import from crisisconnect.instrumentation { NativeSpan }
import from crisisconnect.schema { CrisisConnectHub, Incident, Holds }
import from crisisconnect.views { QueueRow }
import from crisisconnect.store { find_incident, log_decision }
import from crisisconnect.priority { enforce_floor }
import from crisisconnect.ai.models { strong, budget_hook, drain_agent_steps, last_model }
import from crisisconnect.agent_tools { incident_summary_in, vulnerable_flags_in, waiting_time_in }

glob rank_model: any = strong;
obj RankExplanation {
    has inc_id: str;
    has score: float;
    has reason: str;
}
node RankNote {
    has inc_id: str;
    has score: float;
    has reason: str;
    has epoch: int;
}
# The ranker's tools are the shared read-only tools in agent_tools.jac, bound
# to the hub being ranked; without a hub they answer from the queue rows.
obj Ranker {
    has rows: list[QueueRow];
    has hub: CrisisConnectHub | None = None;
    def incident_summary(inc_id: str) -> str {
        with NativeSpan(name="incident_summary", args={"inc_id": inc_id}, kind="tool") as span {
            if self.hub is not None { return span.finish(incident_summary_in(self.hub, inc_id)); }
            for r in self.rows { if r.inc_id == inc_id { return span.finish(r.headline + ": " + r.place + "; " + r.reason); } }
            return span.finish("Not in the current top five");
        }
    }
    def vulnerable_flags(inc_id: str) -> str {
        with NativeSpan(name="vulnerable_flags", args={"inc_id": inc_id}, kind="tool") as span {
            if self.hub is not None { return span.finish(vulnerable_flags_in(self.hub, inc_id)); }
            for r in self.rows { if r.inc_id == inc_id { return span.finish(", ".join(r.vulnerable) or "none"); } }
            return span.finish("none");
        }
    }
    def waiting_time(inc_id: str) -> str {
        with NativeSpan(name="waiting_time", args={"inc_id": inc_id}, kind="tool") as span {
            if self.hub is not None { return span.finish(waiting_time_in(self.hub, inc_id)); }
            for r in self.rows { if r.inc_id == inc_id { return span.finish(r.waiting); } }
            return span.finish("unknown");
        }
    }
    def explain() -> list[RankExplanation] by rank_model(
        tools=[self.incident_summary, self.vulnerable_flags, self.waiting_time],
        max_react_iterations=4, on_iteration=budget_hook, temperature=0.0,
        incl_info={"policy": "Explain the top-five call queue. Message count is never an urgency signal. Never reduce a vulnerable incident below its deterministic score. Scores range 0 to 100. Cite only current incident IDs."}
    );
}

def explain_top(hub: CrisisConnectHub, rows: list[QueueRow]) -> list[QueueRow] {
    top = rows[:5];
    notes = [RankExplanation(inc_id=r.inc_id, score=r.priority, reason=r.reason) for r in top];
    if os.environ.get("CRISISCONNECT_AI", "on") != "off" {
        try { notes = Ranker(rows=top, hub=hub).explain(); } except Exception { return overlay_rank(hub, rows); }
    }
    allowed = [r.inc_id for r in top];
    for old in [hub ->:Holds:->[?:RankNote]] { del old; }
    for note in notes {
        if note.inc_id not in allowed { continue; }
        inc = find_incident(hub, note.inc_id);
        if inc is None { continue; }
        for row in top {
            if row.inc_id == note.inc_id {
                score = enforce_floor(max(0.0, min(100.0, note.score)), row.priority, row.vulnerable);
                hub +>:Holds:+> RankNote(inc_id=note.inc_id, score=score, reason=note.reason, epoch=hub.message_seq);
                log_decision(hub, "ranker", "explain", note.reason, "APPLIED", hub.storm_time, [inc], model=last_model() or "rules", target_label=inc.inc_id);
            }
        }
    }
    for row in drain_agent_steps() {
        log_decision(hub, "ranker", "tool_call", str(row.get("tool", "tool")), "READ_ONLY", hub.storm_time, [], model=last_model() or "rules");
    }
    return overlay_rank(hub, rows);
}

def overlay_rank(hub: CrisisConnectHub, rows: list[QueueRow]) -> list[QueueRow] {
    top = rows[:5];
    for note in [hub ->:Holds:->[?:RankNote]] {
        if note.epoch != hub.message_seq { continue; }
        for row in top {
            if row.inc_id == note.inc_id {
                row.priority = enforce_floor(note.score, row.priority, row.vulnerable);
                row.reason = note.reason;
            }
        }
    }
    top = sorted(top, key=lambda (r: QueueRow) { -r.priority; });
    result = top + rows[5:];
    for (i, row) in enumerate(result) { row.rank = i + 1; }
    return result;
}
