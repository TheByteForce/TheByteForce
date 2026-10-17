"""Deterministic priority score (A5, plain part).

Inputs: vulnerable flags, storm-time waiting, headcount. The number of
messages in an incident is dedup context only and is NEVER urgency: ten
copies of one SOS are not ten times as urgent. A model ranker may re-order
and explain the top 5, but R3 keeps flagged incidents at or above this
score.
"""

import from crisisconnect.schema { CrisisConnectHub, Incident }
import from crisisconnect.store { storm_diff, fmt_minutes, pending_headcount }
import from crisisconnect.referee { VULNERABLE_FLAGS, RefereeOutcome, r3_check }

glob FLAG_WEIGHT: dict[str, float] = {
    "medical": 30.0, "child": 25.0, "elderly": 25.0, "disability": 25.0
};
glob UNKNOWN_FLAG_WEIGHT: float = 10.0;
glob FLAG_CAP: float = 60.0;
glob PER_PERSON: float = 2.5;
glob PERSON_CAP: float = 25.0;
glob WAIT_PER_MINUTE: float = 0.1;
glob WAIT_CAP: float = 15.0;
glob CRITICAL_FLOOR: float = 50.0;

obj PriorityResult {
    has score: float = 0.0;
    has reason: str = "";
    has critical: bool = False;
}

def flag_score(flags: list[str]) -> float {
    total = 0.0;
    for f in flags {
        total += FLAG_WEIGHT.get(f, UNKNOWN_FLAG_WEIGHT);
    }
    return min(total, FLAG_CAP);
}

def is_critical(flags: list[str]) -> bool {
    for f in flags {
        if f in VULNERABLE_FLAGS {
            return True;
        }
    }
    return False;
}

# extra_headcount: an unconfirmed higher count (R6) still raises urgency.
def compute_priority(inc: Incident, storm_now: str, extra_headcount: int) -> PriorityResult {
    if inc.status == "RESOLVED" or inc.status == "HANDED_OVER" {
        return PriorityResult(score=0.0, reason="closed or handed over", critical=False);
    }
    people = max(inc.headcount, extra_headcount);
    wait_min = storm_diff(storm_now, inc.first_seen);
    score = flag_score(inc.vulnerable);
    score += min(people * PER_PERSON, PERSON_CAP);
    score += min(wait_min * WAIT_PER_MINUTE, WAIT_CAP);
    parts: list[str] = [];
    if len(inc.vulnerable) > 0 {
        parts.append(" + ".join(inc.vulnerable) + " flagged");
    }
    if people > 0 {
        parts.append(f"{people} people");
    }
    parts.append("waiting " + fmt_minutes(wait_min));
    if inc.status == "CLOSE_PROPOSED" {
        score -= 25.0;
        parts.append("close proposed (call pending)");
    } elif inc.status == "STALE" {
        score -= 5.0;
        parts.append("quiet for a while");
    }
    critical = is_critical(inc.vulnerable);
    if critical and score < CRITICAL_FLOOR {
        score = CRITICAL_FLOOR;
        parts.append("critical floor");
    }
    score = max(0.0, min(100.0, score));
    return PriorityResult(score=round(score, 1), reason="; ".join(parts), critical=critical);
}

# R3: whatever a model proposes, a flagged incident never drops below this score.
def enforce_floor(proposed: float, deterministic: float, vulnerable: list[str]) -> float {
    if r3_check(proposed, deterministic, vulnerable).outcome == RefereeOutcome.BLOCKED {
        return deterministic;
    }
    return proposed;
}

def priority_now(hub: CrisisConnectHub, inc: Incident) -> PriorityResult {
    return compute_priority(inc, hub.storm_time, pending_headcount(hub, inc.inc_id));
}

# Recompute and store the incident's priority.
def refresh_priority(hub: CrisisConnectHub, inc: Incident) -> PriorityResult {
    res = priority_now(hub, inc);
    inc.priority = res.score;
    return res;
}
