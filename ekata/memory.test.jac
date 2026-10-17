"""Agent memory tests: derived views on private hubs."""

import from ekata.store { fresh_hub, log_decision }

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
