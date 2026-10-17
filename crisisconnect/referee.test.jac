"""One test per referee rule (plus the R1/R2 edge cases that matter for the demo)."""

test "R1 exact phone match with a good score is auto-merged" {
    v = referee_merge("INC-001", "STRONG", 0.9, 1, True);
    assert v.outcome == RefereeOutcome.APPLIED;
    assert v.rule == "R1";
}

test "R1 strong detail with a low score goes to a person" {
    v = referee_merge("INC-001", "STRONG", 0.3, 1, True);
    assert v.outcome == RefereeOutcome.NEEDS_HUMAN;
}

test "R1 shared surname on the same road is never a strong detail" {
    # archetype 12: two different families, same surname, same road
    v = referee_merge("INC-001", "WEAK", 0.95, 1, True);
    assert v.outcome == RefereeOutcome.BLOCKED;
    assert v.rule == "R1";
}

test "R1 full name without a household place is not auto-merged" {
    v = referee_merge("INC-001", "MEDIUM", 0.95, 1, True);
    assert v.outcome == RefereeOutcome.BLOCKED;
}

test "R2 a blocked proposal gets one retry then becomes a new incident" {
    first = referee_merge("INC-001", "WEAK", 0.9, 1, True);
    assert first.outcome == RefereeOutcome.BLOCKED;
    second = referee_merge("INC-001", "WEAK", 0.9, 2, True);
    assert second.outcome == RefereeOutcome.NEW_INCIDENT;
}

test "R2 a partial match after the retry is proposed to a person" {
    second = referee_merge("INC-001", "MEDIUM", 0.8, 2, True);
    assert second.outcome == RefereeOutcome.NEEDS_HUMAN;
}

test "R2 a proposal outside the candidate list is blocked" {
    v = referee_merge("INC-999", "", 0.9, 1, False);
    assert v.outcome == RefereeOutcome.BLOCKED;
}

test "R2 an empty choice means a new incident" {
    v = referee_merge("", "", 0.0, 1, False);
    assert v.outcome == RefereeOutcome.NEW_INCIDENT;
}

test "R3 a model cannot rank a vulnerable incident below the deterministic score" {
    low = r3_check(20.0, 62.0, ["elderly"]);
    assert low.outcome == RefereeOutcome.BLOCKED;
    ok = r3_check(70.0, 62.0, ["elderly"]);
    assert ok.outcome == RefereeOutcome.APPLIED;
    free = r3_check(20.0, 62.0, []);
    assert free.outcome == RefereeOutcome.APPLIED;
}

test "R4 confirming or resolving needs a call log" {
    assert r4_status_change("CONFIRMED", False).outcome == RefereeOutcome.BLOCKED;
    assert r4_status_change("RESOLVED", False).outcome == RefereeOutcome.BLOCKED;
    assert r4_status_change("CONFIRMED", True).outcome == RefereeOutcome.APPLIED;
    assert r4_status_change("RESOLVED", True).outcome == RefereeOutcome.APPLIED;
}

test "R4 already rescued only proposes closing" {
    v = r4_status_change("CLOSE_PROPOSED", False);
    assert v.outcome == RefereeOutcome.APPLIED;
    assert v.rule == "R4";
}

test "R5 two desks cannot claim the same incident" {
    assert r5_claim("Desk A", "Desk B").outcome == RefereeOutcome.BLOCKED;
    assert r5_claim("Desk A", "Desk A").outcome == RefereeOutcome.APPLIED;
    assert r5_claim("", "Desk B").outcome == RefereeOutcome.APPLIED;
}

test "R6 a headcount contradiction re-opens verification instead of overwriting" {
    v = r6_contradiction("3", "6");
    assert v.outcome == RefereeOutcome.NEEDS_HUMAN;
    assert v.rule == "R6";
    same = r6_contradiction("3", "3");
    assert same.outcome == RefereeOutcome.APPLIED;
    unknown = r6_contradiction("", "6");
    assert unknown.outcome == RefereeOutcome.APPLIED;
}

test "R7 rumours never enter the call queue" {
    assert r7_queue_eligible("RUMOUR").outcome == RefereeOutcome.BLOCKED;
    assert r7_queue_eligible("SOS").outcome == RefereeOutcome.APPLIED;
    assert r7_queue_eligible("UPDATE").outcome == RefereeOutcome.APPLIED;
}

test "R13 an incomplete decision is rejected" {
    assert r13_decision_complete("resolver", "propose", "", "APPLIED").outcome == RefereeOutcome.BLOCKED;
    assert r13_decision_complete("", "propose", "why", "APPLIED").outcome == RefereeOutcome.BLOCKED;
    assert r13_decision_complete("resolver", "propose", "why", "APPLIED").outcome == RefereeOutcome.APPLIED;
}

test "R14 only the single writer applies, and only after the referee allows it" {
    assert r14_apply_allowed("resolver", RefereeOutcome.APPLIED).outcome == RefereeOutcome.BLOCKED;
    assert r14_apply_allowed("writer", RefereeOutcome.BLOCKED).outcome == RefereeOutcome.BLOCKED;
    assert r14_apply_allowed("writer", RefereeOutcome.NEEDS_HUMAN).outcome == RefereeOutcome.BLOCKED;
    assert r14_apply_allowed("writer", RefereeOutcome.APPLIED).outcome == RefereeOutcome.APPLIED;
    assert r14_apply_allowed("writer", RefereeOutcome.NEW_INCIDENT).outcome == RefereeOutcome.APPLIED;
}

test "R12 a real office title is blocked, an invented issuer passes" {
    assert r12_no_real_names("Notice from the DMC: move to higher ground").outcome == RefereeOutcome.BLOCKED;
    assert r12_no_real_names("NBRO landslide alert for tonight").outcome == RefereeOutcome.BLOCKED;
    assert r12_no_real_names("Disaster Management Centre says").outcome == RefereeOutcome.BLOCKED;
    assert r12_no_real_names("District Flood Desk: shelters are open").outcome == RefereeOutcome.APPLIED;
    assert r12_no_real_names("Ministry Flood Relief Desk (invented scam office)").outcome == RefereeOutcome.APPLIED;
}
