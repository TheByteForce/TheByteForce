"""Agent memory tests: derived views on private hubs."""

import from ekata.store { fresh_hub, log_decision, all_proposals, find_message }
import from ekata.ai.models { call_log, agent_steps }

def mk_msg(hub: EkataHub, mid: str) -> Message {
    m = Message(msg_id=mid, text="x");
    hub +>:Holds:+> m;
    return m;
}

def mk_inc(hub: EkataHub, iid: str) -> Incident {
    i = Incident(inc_id=iid);
    hub +>:Holds:+> i;
    return i;
}

def seed_run(hub: EkataHub) -> Message {
    m = mk_msg(hub, "W-001");
    log_decision(hub, "referee", "merge_check", "R1: weak tier blocked", "BLOCKED", "18:01", [m], 0.5, "rules");
    log_decision(hub, "intake", "extract", "parsed the sos", "APPLIED", "18:00", [m], 0.9, "model-a");
    log_decision(hub, "resolver", "merge_retry", "tried again", "APPLIED", "18:02", [m], 0.7, "model-b");
    log_decision(hub, "referee", "merge_check", "R2: second block, new incident", "NEW_INCIDENT", "18:03", [m], 1.0, "rules");
    return m;
}

test "steps are ordered by seq" {
    hub = fresh_hub("t-mem-1");
    seed_run(hub);
    v = agent_run_in(hub, "W-001");
    assert v.found;
    assert len(v.steps) == 4;
    assert v.steps[0].seq == 1 and v.steps[3].seq == 4;
    assert v.steps[1].agent == "intake";
    assert v.agents == ["referee", "intake", "resolver"];
}

test "rule id is parsed from the reason" {
    hub = fresh_hub("t-mem-2");
    seed_run(hub);
    v = agent_run_in(hub, "W-001");
    assert v.steps[0].rule == "R1";
    assert v.steps[1].rule == "";
    assert v.steps[3].rule == "R2";
}

test "blocked, retries, llm and rule steps are counted" {
    hub = fresh_hub("t-mem-3");
    seed_run(hub);
    v = agent_run_in(hub, "W-001");
    assert v.blocked == 1;
    assert v.retries == 1;
    assert v.llm_steps == 2;
    assert v.rule_steps == 2;
    assert v.models == ["model-a", "model-b"];
    assert v.outcome == "NEW_INCIDENT";
}

test "unknown message is not found" {
    hub = fresh_hub("t-mem-4");
    v = agent_run_in(hub, "W-999");
    assert not v.found;
    assert len(v.steps) == 0;
}

test "rule stats count outcomes per rule" {
    hub = fresh_hub("t-mem-5");
    m = mk_msg(hub, "W-001");
    log_decision(hub, "referee", "a", "R1: ok", "APPLIED", "18:00", [m]);
    log_decision(hub, "referee", "a", "R1: no", "BLOCKED", "18:00", [m]);
    log_decision(hub, "referee", "a", "R1: ask", "NEEDS_HUMAN", "18:00", [m]);
    log_decision(hub, "referee", "a", "R2: new", "NEW_INCIDENT", "18:00", [m]);
    log_decision(hub, "intake", "a", "plain reason", "APPLIED", "18:00", [m]);
    rows = rule_stats_in(hub);
    assert len(rows) == 14;
    assert rows[0].rule == "R1" and rows[0].total == 3;
    assert rows[0].applied == 1 and rows[0].blocked == 1 and rows[0].needs_human == 1;
    assert rows[1].new_incident == 1;
    assert rows[2].total == 0;
}

test "pattern_for classifies candidate reasons" {
    assert pattern_for(["[STRONG] exact phone match 07X"]) == "STRONG:phone";
    assert pattern_for(["[STRONG] same full name 'A B' + same household place 'No 5'"]) == "STRONG:name+house";
    assert pattern_for(["[MEDIUM] same full name 'A B' but no shared household-level place"]) == "MEDIUM:name-only";
    assert pattern_for(["[MEDIUM] same household-level place 'No 5' but no matching name"]) == "MEDIUM:house-only";
    assert pattern_for(["[WEAK] same surname 'Silva' on the same road"]) == "WEAK:surname+road";
    assert pattern_for(["nothing"]) == "";
}

def seed_proposal(hub: EkataHub, inc: Incident, mid: str, status: str, tag: str) {
    m = mk_msg(hub, mid);
    m +>:Candidate(reasons=[tag]):+> inc;
    hub +>:Holds:+> MergeProposal(msg_id=mid, inc_id="INC-001", status=status);
}

test "precedents group desk decisions by pattern" {
    hub = fresh_hub("t-mem-7");
    inc = mk_inc(hub, "INC-001");
    weak = "[WEAK] same surname 'Silva' on the same road";
    seed_proposal(hub, inc, "W-001", "REJECTED", weak);
    seed_proposal(hub, inc, "W-002", "REJECTED", weak);
    seed_proposal(hub, inc, "W-003", "APPROVED", "[STRONG] exact phone match 07X");
    seed_proposal(hub, inc, "W-004", "PENDING", weak);
    ps = precedents_in(hub);
    assert len(ps) == 2;
    assert ps[0].pattern == "STRONG:phone" and ps[0].approved == 1 and ps[0].rejected == 0;
    assert ps[1].pattern == "WEAK:surname+road" and ps[1].rejected == 2 and len(ps[1].ids) == 2;
}

test "desk_precedents text" {
    hub = fresh_hub("t-mem-8");
    inc = mk_inc(hub, "INC-001");
    seed_proposal(hub, inc, "W-001", "REJECTED", "[WEAK] same surname 'Silva' on the same road");
    t = desk_precedents_in(hub, "WEAK:surname+road");
    assert "REJECTED 1 and APPROVED 0" in t;
    assert "WEAK:surname+road" in t;
    assert desk_precedents_in(hub, "STRONG:phone") == "no precedents yet";
}

# ---------- persisted memory (private hub + private memory hub) ----------

def seed_ordered(hub: EkataHub, mid: str, ma: str, mb: str) -> Message {
    m = mk_msg(hub, mid);
    m.kind = "SOS";
    log_decision(hub, "intake", "extract", "parsed the sos", "APPLIED", "18:00", [m], 0.9, ma);
    log_decision(hub, "referee", "merge_check", "R1: weak tier blocked", "BLOCKED", "18:01", [m], 0.5, "rules");
    log_decision(hub, "referee", "merge_check", "R2: second block", "NEW_INCIDENT", "18:02", [m], 1.0, mb);
    return m;
}

test "record_run builds an ordered run with Next chain and Cites" {
    hub = fresh_hub("t-mem-r1");
    mem = "t-mem-hub-1";
    reset_memory(mem);
    m = seed_ordered(hub, "W-001", "rules", "rules");
    run = record_run(hub, m, memory_mark(), mem);
    assert run.run_id == "RUN-001";
    assert run.lane == "SOS";
    assert run.mode == "RULES";
    mh = get_memory_hub(mem);
    assert len([mh ->:Remembers:->[?:AgentRun]]) == 1;
    steps = [run ->:Step:->[?:Decision]];
    assert len(steps) == 3;
    ordered = sorted(steps, key=lambda (d: Decision) { d.seq; });
    firsts = [ordered[0] ->:Next:->[?:Decision]];
    assert len(firsts) == 1 and firsts[0].seq == ordered[1].seq;
    assert len([ordered[2] ->:Next:->[?:Decision]]) == 0;
    ed = [edge run ->:Step:-> ordered[2]];
    assert ed[0].order == 3;
    assert len([ordered[0] ->:Cites:->[?:Rule]]) == 0;
    cited = [ordered[1] ->:Cites:->[?:Rule]];
    assert len(cited) == 1 and cited[0].rule_id == "R1";
    again = record_run(hub, m, memory_mark(), mem);
    assert again.run_id == "RUN-001";
    counts = rule_citations_in(mem);
    assert counts[0].rule == "R1" and counts[0].cites == 1;
    assert counts[1].cites == 1;
}

test "LlmCall and ToolCall rows come from buffers since the mark" {
    hub = fresh_hub("t-mem-r2");
    mem = "t-mem-hub-2";
    reset_memory(mem);
    call_log.append({"caller": "before", "model": "old", "latency_ms": 1.0, "total_tokens": 99, "status": "success", "error": ""});
    mark = memory_mark();
    call_log.append({"caller": "extract", "model": "model-a", "latency_ms": 12.5, "total_tokens": 40, "status": "success", "error": ""});
    call_log.append({"caller": "pick", "model": "model-b", "latency_ms": 7.0, "total_tokens": 60, "status": "error", "error": "provider failure"});
    agent_steps.append({"iteration": 1, "tool": "lookup", "result_preview": "ok", "tokens": 10, "cost": 0.0});
    m = seed_ordered(hub, "W-001", "model-a", "rules");
    run = record_run(hub, m, mark, mem);
    assert run.llm_calls == 2 and run.tokens == 100;
    assert run.mode == "LIVE";
    lcs = [run ->:Called:->[?:LlmCall]];
    assert len(lcs) == 2;
    assert sorted([c.model for c in lcs]) == ["model-a", "model-b"];
    tcs = [run ->:Used:->[?:ToolCall]];
    assert len(tcs) == 1 and tcs[0].tool == "lookup";
    v = agent_run_in(hub, "W-001", mem);
    assert v.run_id == "RUN-001" and v.llm_calls == 2 and v.tokens == 100;
    assert sorted(v.call_models) == ["model-a", "model-b"];
    reset_memory(mem);
}

test "mode is CACHED when any decision model is cached" {
    hub = fresh_hub("t-mem-r3");
    mem = "t-mem-hub-3";
    reset_memory(mem);
    m = seed_ordered(hub, "W-001", "cached:model-a", "rules");
    run = record_run(hub, m, memory_mark(), mem);
    assert run.mode == "CACHED";
    assert usage_ledger_in(mem).cached_calls >= 1;
}

test "feedback is materialised once" {
    hub = fresh_hub("t-mem-r4");
    mem = "t-mem-hub-4";
    reset_memory(mem);
    inc = mk_inc(hub, "INC-001");
    seed_proposal(hub, inc, "W-010", "REJECTED", "[WEAK] same surname 'Silva' on the same road");
    p = all_proposals(hub)[0];
    p.decided_by = "desk-a";
    pm = find_message(hub, "W-010");
    assert pm is not None;
    log_decision(hub, "desk", "merge_rejected", "desk-a kept apart", "REJECTED", "18:05", [pm, inc, p], 1.0, "human");
    m = seed_ordered(hub, "W-001", "rules", "rules");
    record_run(hub, m, memory_mark(), mem);
    m2 = seed_ordered(hub, "W-002", "rules", "rules");
    record_run(hub, m2, memory_mark(), mem);
    mh = get_memory_hub(mem);
    fbs = [mh ->:Remembers:->[?:Feedback]];
    assert len(fbs) == 1;
    assert fbs[0].action == "REJECTED" and fbs[0].pattern == "WEAK:surname+road";
    assert fbs[0].actor == "desk-a";
    assert len([fbs[0] ->:On:->[?:MergeProposal]]) == 1;
}

test "reset empties runs but keeps the ledger, which accumulates" {
    hub = fresh_hub("t-mem-r5");
    mem = "t-mem-hub-5";
    reset_memory(mem);
    base = usage_ledger_in(mem);
    m = seed_ordered(hub, "W-001", "rules", "rules");
    record_run(hub, m, memory_mark(), mem);
    m2 = seed_ordered(hub, "W-002", "rules", "rules");
    record_run(hub, m2, memory_mark(), mem);
    led = usage_ledger_in(mem);
    assert led.rule_runs == base.rule_runs + 2;
    reset_memory(mem);
    mh = get_memory_hub(mem);
    assert len([mh ->:Remembers:->[?:AgentRun]]) == 0;
    assert len([mh ->:Remembers:->[?:Rule]]) == 14;
    after = usage_ledger_in(mem);
    assert after.rule_runs == led.rule_runs;
    assert after.since == led.since;
}
