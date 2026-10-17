"""Referee: plain Jac rules, no LLM (plan section 12: R1-R7, R12, R13, R14).

Every rule is a pure function over typed inputs and returns a RefereeVerdict
(outcome + rule id + reason). The coordinator gathers the facts (from the
graph) and the referee decides; nothing here touches the graph.
Tier names come from blocking: STRONG, MEDIUM, WEAK (or "" for no evidence).
"""

import re;
import from crisisconnect.schema { RefereeOutcome }

# A merge proposal scoring below this goes to a person even with strong evidence.
glob MIN_MERGE_SCORE: float = 0.5;

# The only vulnerable flags the system recognises (R3 floors them).
glob VULNERABLE_FLAGS: list[str] = ["medical", "child", "elderly", "disability"];

glob OPEN_STATUSES: list[str] = ["NEW", "VERIFYING", "CONFIRMED", "CLOSE_PROPOSED", "STALE"];

obj RefereeVerdict {
    has outcome: RefereeOutcome = RefereeOutcome.APPLIED;
    has rule: str = "";
    has reason: str = "";
}

def mk_verdict(outcome: RefereeOutcome, rule: str, reason: str) -> RefereeVerdict {
    return RefereeVerdict(outcome=outcome, rule=rule, reason=reason);
}

# R1 + R2: may this proposed merge be applied?
# tier: the strongest shared evidence between the message and the proposed
# incident, as computed by blocking (STRONG / MEDIUM / WEAK / "").
# attempt: 1 for the first proposal, 2 for the retry after a block.
def referee_merge(
    chosen_inc_id: str,
    tier: str,
    score: float,
    attempt: int,
    in_candidates: bool
) -> RefereeVerdict {
    if chosen_inc_id == "" {
        return mk_verdict(RefereeOutcome.NEW_INCIDENT, "R2", "the resolver proposed a new incident");
    }
    if not in_candidates {
        if attempt <= 1 {
            return mk_verdict(
                RefereeOutcome.BLOCKED, "R2",
                "the proposed incident is not a Candidate: no shared identifier links it to this message"
            );
        }
        return mk_verdict(
            RefereeOutcome.NEW_INCIDENT, "R2",
            "blocked twice (not a Candidate): treated as a new incident"
        );
    }
    if tier == "STRONG" {
        if score >= MIN_MERGE_SCORE {
            return mk_verdict(
                RefereeOutcome.APPLIED, "R1",
                "strong shared detail (exact phone, or full name plus household-level place): auto-merge allowed"
            );
        }
        return mk_verdict(
            RefereeOutcome.NEEDS_HUMAN, "R1",
            "strong shared detail but the resolver score is below the threshold: a person decides"
        );
    }
    if tier == "MEDIUM" {
        if attempt <= 1 {
            return mk_verdict(
                RefereeOutcome.BLOCKED, "R2",
                "no strong shared detail (a full name or a household place alone is not enough): cite an exact phone or full name plus household place, or answer new incident"
            );
        }
        if score >= MIN_MERGE_SCORE {
            return mk_verdict(
                RefereeOutcome.NEEDS_HUMAN, "R1",
                "only a partial match after a retry: proposed to a person, never auto-merged"
            );
        }
        return mk_verdict(
            RefereeOutcome.NEW_INCIDENT, "R2",
            "partial match with a low score after a retry: treated as a new incident"
        );
    }
    if attempt <= 1 {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R1",
            "a shared surname or a road- or village-level place never counts as a strong detail: cite an exact phone or full name plus household place, or answer new incident"
        );
    }
    return mk_verdict(
        RefereeOutcome.NEW_INCIDENT, "R2",
        "blocked twice (no strong shared detail): treated as a new incident"
    );
}

# R3: a model can never lower the priority of a medical / child / elderly /
# disability incident below the deterministic score.
def r3_check(proposed: float, deterministic: float, vulnerable: list[str]) -> RefereeVerdict {
    flagged = False;
    for f in vulnerable {
        if f in VULNERABLE_FLAGS {
            flagged = True;
        }
    }
    if flagged and proposed < deterministic {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R3",
            "a vulnerable-flagged incident cannot be ranked below its deterministic score"
        );
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R3", "priority respects the deterministic floor");
}

# R4: CONFIRMED and RESOLVED need a CallLog; "already rescued" only proposes closing.
def r4_status_change(new_status: str, has_call_log: bool) -> RefereeVerdict {
    if (new_status == "CONFIRMED" or new_status == "RESOLVED") and not has_call_log {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R4",
            "an incident cannot become " + new_status + " without a logged call"
        );
    }
    if new_status == "CLOSE_PROPOSED" {
        return mk_verdict(
            RefereeOutcome.APPLIED, "R4",
            "closing is only proposed; a logged call must resolve it"
        );
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R4", "status change allowed");
}

# R5: two desks cannot claim the same incident (compared by desk name).
# claimed_by is the desk currently holding an active claim ("" if none).
def r5_claim(claimed_by: str, desk: str) -> RefereeVerdict {
    if claimed_by != "" and claimed_by != desk {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R5",
            "already claimed by " + claimed_by + "; " + desk + " cannot claim it too"
        );
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R5", "claim allowed");
}

# R6: a contradiction (headcount or location) re-opens verification instead of
# overwriting. NEEDS_HUMAN here means: keep the old value, record the new one
# as pending, and re-open verification.
def r6_contradiction(old_value: str, new_value: str) -> RefereeVerdict {
    if old_value != "" and new_value != "" and old_value != new_value {
        return mk_verdict(
            RefereeOutcome.NEEDS_HUMAN, "R6",
            "contradiction (" + old_value + " vs " + new_value + "): verification re-opened, value not overwritten"
        );
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R6", "no contradiction");
}

# R7: rumours never enter the call queue.
def r7_queue_eligible(kind: str) -> RefereeVerdict {
    if kind == "RUMOUR" {
        return mk_verdict(RefereeOutcome.BLOCKED, "R7", "rumours never enter the call queue");
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R7", "eligible for an incident");
}

# R12: real people's names and real office titles never appear in fixtures or
# generated warnings. Fixtures and seeded bulletins use invented issuers; a
# test runs this over every fixture so a real agency can't slip back in.
glob REAL_OFFICE_TITLES: list[str] = [
    "disaster management centre", "dmc", "nbro", "national building research",
    "irrigation department", "department of meteorology", "met department",
    "red cross", "slcert", "sarvodaya"
];

def r12_no_real_names(text: str) -> RefereeVerdict {
    low = text.lower();
    for title in REAL_OFFICE_TITLES {
        if re.search(r"\b" + re.escape(title) + r"\b", low) {
            return mk_verdict(
                RefereeOutcome.BLOCKED, "R12",
                "names a real office (" + title + "); use an invented issuer"
            );
        }
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R12", "no real office titles");
}

# R13: every applied change carries a Decision with agent, action and reason.
def r13_decision_complete(agent: str, action: str, reason: str, outcome: str) -> RefereeVerdict {
    if agent == "" or action == "" or reason == "" or outcome == "" {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R13",
            "a decision needs an agent, an action, a reason and an outcome"
        );
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R13", "decision is complete");
}

# R14: model tools are read-only. Only the single writer ("writer") may apply
# a change, and only after the referee allowed it.
def r14_apply_allowed(actor: str, outcome: RefereeOutcome) -> RefereeVerdict {
    if actor != "writer" {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R14",
            actor + " is not the single writer; model tools are read-only"
        );
    }
    if outcome == RefereeOutcome.BLOCKED or outcome == RefereeOutcome.NEEDS_HUMAN {
        return mk_verdict(
            RefereeOutcome.BLOCKED, "R14",
            "the referee did not allow a direct change"
        );
    }
    return mk_verdict(RefereeOutcome.APPLIED, "R14", "the single writer may apply");
}
