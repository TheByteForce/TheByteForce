"""Freshness check (A4): plain Jac typed-field comparison, no LLM.

Compares what a message says (Facts) with what the incident holds.
  headcount or location differs -> Contradicts edge, the old value is kept,
      the new one is stored as a PendingChange and verification is re-opened (R6)
  kind UPDATE with "rescued"    -> CLOSE_PROPOSED only; a call must resolve it (R4)
Non-conflicting facts (new flags, needs, a first headcount or place) are merged.
"""

import from crisisconnect.schema {
    CrisisConnectHub, Message, Incident, Contradicts, Holds, RefereeOutcome
}
import from crisisconnect.store {
    PendingChange, log_decision, messages_of, change_status, normalise_place,
    place_compatible, storm_minutes
}
import from crisisconnect.referee { r6_contradiction }

obj Facts {
    has kind: str = "SOS";
    has headcount: int = 0;
    has vulnerable: list[str] = [];
    has needs: list[str] = [];
    has place: str = "";
    has summary: str = "";
    has rescued: bool = False;
}

obj Finding {
    has fld: str;
    has old_value: str = "";
    has new_value: str = "";
}

obj FreshnessResult {
    has findings: list[Finding] = [];
    has propose_close: bool = False;
}

# Read-only comparison of a message's facts with an incident.
def check_freshness(inc: Incident, facts: Facts) -> FreshnessResult {
    res = FreshnessResult();
    if facts.headcount > 0 and inc.headcount > 0 and facts.headcount != inc.headcount {
        res.findings.append(
            Finding(fld="headcount", old_value=str(inc.headcount), new_value=str(facts.headcount))
        );
    }
    if facts.place != "" and inc.place != "" {
        if not place_compatible(normalise_place(inc.place), normalise_place(facts.place)) {
            res.findings.append(Finding(fld="place", old_value=inc.place, new_value=facts.place));
        }
    }
    if facts.rescued and facts.kind == "UPDATE" {
        res.propose_close = True;
    }
    return res;
}

# The latest earlier message of the incident (what a contradiction points at).
def previous_message(inc: Incident, msg: Message) -> Message | None {
    prev: Message | None = None;
    for m in messages_of(inc) {
        if m.seq < msg.seq {
            prev = m;
        }
    }
    return prev;
}

# Merge a message's facts into an incident and run the freshness rules.
# Returns human-readable notes describing what changed.
def apply_facts(
    hub: CrisisConnectHub,
    msg: Message,
    inc: Incident,
    facts: Facts,
    storm_time: str
) -> list[str] {
    notes: list[str] = [];
    res = check_freshness(inc, facts);
    prev = previous_message(inc, msg);

    for f in facts.vulnerable {
        if f not in inc.vulnerable {
            inc.vulnerable = inc.vulnerable + [f];
            notes.append("flag " + f + " added");
        }
    }
    for n in facts.needs {
        if n not in inc.needs {
            inc.needs = inc.needs + [n];
        }
    }
    if inc.headcount == 0 and facts.headcount > 0 {
        inc.headcount = facts.headcount;
        notes.append(f"headcount set to {facts.headcount}");
    }
    if inc.place == "" and facts.place != "" {
        inc.place = facts.place;
        notes.append("place set to " + facts.place);
    }
    if inc.summary == "" and facts.summary != "" {
        inc.summary = facts.summary;
    }

    for fd in res.findings {
        v = r6_contradiction(fd.old_value, fd.new_value);
        if v.outcome != RefereeOutcome.NEEDS_HUMAN {
            continue;
        }
        pc = PendingChange(
            inc_id=inc.inc_id, fld=fd.fld, old_value=fd.old_value, new_value=fd.new_value,
            msg_id=msg.msg_id, storm_time=storm_time
        );
        hub +>:Holds:+> pc;
        if prev is not None {
            msg +>:Contradicts(field=fd.fld):+> prev;
        }
        reopened = False;
        if inc.status == "CONFIRMED" or inc.status == "HANDED_OVER" {
            inc.status = "VERIFYING";
            inc.claimed_by = "";
            reopened = True;
        }
        note = fd.fld + ": " + fd.old_value + " vs " + fd.new_value;
        notes.append("contradiction " + note);
        log_decision(
            hub, "freshness", "contradiction",
            v.reason + " [" + note + "]" + (" status back to VERIFYING." if reopened else ""),
            v.outcome.value, storm_time, [msg, inc],
            confidence=1.0, model="rules", target_label=inc.inc_id
        );
    }

    if res.propose_close and inc.status in ["NEW", "VERIFYING", "CONFIRMED", "STALE"] {
        change_status(inc, "CLOSE_PROPOSED");
        notes.append("close proposed (rescued)");
        log_decision(
            hub, "freshness", "propose_close",
            "an update says the household was rescued; closing is only proposed until a call is logged (R4)",
            RefereeOutcome.APPLIED.value, storm_time, [msg, inc],
            confidence=1.0, model="rules", target_label=inc.inc_id
        );
    }

    if storm_minutes(storm_time) > storm_minutes(inc.last_seen) {
        inc.last_seen = storm_time;
    }
    if inc.status == "STALE" {
        inc.status = "NEW";
        notes.append("woken from STALE");
    }
    return notes;
}
