"""One verified household, end to end: every message, agent proposal, safety
rule, human decision and resulting action recorded about it, in order.

Read straight off the graph: Decisions point at the incident, its messages,
its calls, its relief requests and the appeals that claim it (About edges),
so the story needs no separate log.
"""

import from crisisconnect.schema {
    CrisisConnectHub, Holds, Incident, Message, Decision, About, Appeal, ClaimsFor, CallLog, Logged,
    ResourceRequest, RequestFor
}
import from crisisconnect.store { find_incident, messages_of, storm_minutes }
import from crisisconnect.casework { household_record, verifying_call_of }

obj TimelineStep {
    has seq: int;
    has time: str;
    has stage: str;
    has title: str;
    has detail: str = "";
    has actor: str = "";
    has model: str = "";
    has outcome: str = "";
    has confidence: float = 0.0;
}

obj HouseholdTimeline {
    has found: bool = False;
    has inc_id: str = "";
    has place: str = "";
    has status: str = "";
    has headcount: int = 0;
    has vulnerable: list[str] = [];
    has verified: bool = False;
    has record: str = "";
    has messages: int = 0;
    has appeals: list[str] = [];
    has steps: list[TimelineStep] = [];
}

# Where a decision sits in the chain the judges should see:
# evidence -> agent proposal -> rule applied -> human decision -> action.
def stage_of(d: Decision) -> str {
    if d.model == "human" or d.agent in ["desk", "officer", "ngo", "citizen", "district", "admin"] {
        return "Human decision";
    }
    if d.agent in ["referee", "blocking", "appeal_referee", "freshness"] or d.outcome in ["BLOCKED", "NEEDS_HUMAN"] {
        return "Rule applied";
    }
    if d.agent in ["intake", "resolver", "ranker", "appeal_investigator"] {
        return "Agent proposal";
    }
    return "Action";
}

glob AGENT_NAMES: dict[str, str] = {
    "intake": "Intake agent",
    "resolver": "Resolver agent",
    "referee": "Safety referee",
    "blocking": "Merge safety check",
    "priority": "Priority rules",
    "ranker": "Ranking agent",
    "router": "Route agent",
    "matcher": "Relief matcher",
    "desk": "Division officer",
    "officer": "Division officer",
    "ngo": "Relief group",
    "citizen": "Citizen",
    "district": "District desk",
    "admin": "District desk",
    "appeal_referee": "Appeal referee",
    "appeal_investigator": "Appeal investigator",
    "freshness": "Freshness rules"
};

def title_of(d: Decision) -> str {
    a = d.action;
    titles = {
        "extract": "Read the message",
        "choose": "Proposed which household this is",
        "choose_retry": "Proposed again after a rule check",
        "find_candidates": "Found possible same-household cases",
        "referee_merge": "Checked the merge against safety rules",
        "referee_merge_retry": "Checked the retry against safety rules",
        "merge_approved": "Confirmed the merge",
        "merge_rejected": "Kept the cases separate",
        "call_logged": "Called the household",
        "status_change": "Updated the household status",
        "claim_blocked": "Blocked a second desk taking the case",
        "route_request": "Sent the request to a relief group",
        "decline": "Declined the request",
        "accept": "Accepted the request",
        "dispatched": "Set off with the help",
        "delivered": "Recorded the delivery",
        "no_cover": "Found no eligible group",
        "duplicate_blocked": "Blocked a duplicate request",
        "repeat_flagged": "Flagged a repeat delivery",
        "pin_gn": "Placed the household in its GN division",
        "pin_location": "Dropped a pin for the household",
        "verdict": "Checked an appeal that names this household",
        "plan_route": "Planned a rescue run",
        "score": "Re-scored the household's priority",
        "alert_override": "Set the alert level",
        "apply_facts": "Updated the household facts",
        "call_rejected": "Rejected an unknown call outcome"
    };
    return titles.get(a, " ".join(a.split("_")).capitalize());
}

def step_of(d: Decision) -> TimelineStep {
    return TimelineStep(
        seq=d.seq, time=d.storm_time, stage=stage_of(d), title=title_of(d), detail=d.reason,
        actor=AGENT_NAMES.get(d.agent, d.agent), model=d.model, outcome=d.outcome, confidence=d.confidence
    );
}

def build_timeline(hub: CrisisConnectHub, inc_id: str) -> HouseholdTimeline {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return HouseholdTimeline(found=False, inc_id=inc_id);
    }
    msgs = messages_of(inc);
    targets: list[any] = [inc] + msgs;
    targets = targets + [c for c in [inc <-:Logged:<-[?:CallLog]]];
    targets = targets + [r for r in [inc <-:RequestFor:<-[?:ResourceRequest]]];
    appeals = [a for a in [inc <-:ClaimsFor:<-[?:Appeal]]];
    targets = targets + appeals;
    seen: list[int] = [];
    steps: list[TimelineStep] = [];
    last_score: TimelineStep | None = None;
    for t in targets {
        for d in [t <-:About:<-[?:Decision]] {
            if d.seq in seen or d.outcome == "READ_ONLY" {
                continue;
            }
            seen.append(d.seq);
            st = step_of(d);
            # Keep only the latest priority re-score; the rest is noise for a reader.
            if d.action == "score" {
                if last_score is None or st.seq > last_score.seq {
                    last_score = st;
                }
                continue;
            }
            steps.append(st);
        }
    }
    if last_score is not None {
        steps.append(last_score);
    }
    # Each message is evidence, placed at its arrival.
    for m in msgs {
        steps.append(TimelineStep(seq=-1, time=m.storm_time, stage="Evidence", title=f"Message {m.msg_id} by {m.channel.lower() or 'web'}", detail=m.text, actor="Citizen"));
    }
    ordered = sorted(steps, key=lambda (s: TimelineStep) { (storm_minutes(s.time) if s.time != "" else 0, 0 if s.seq < 0 else 1, s.seq); });
    return HouseholdTimeline(
        found=True, inc_id=inc.inc_id, place=inc.place, status=inc.status, headcount=inc.headcount,
        vulnerable=inc.vulnerable, verified=verifying_call_of(inc) is not None,
        record=household_record(inc), messages=len(msgs), appeals=[a.appeal_id for a in appeals], steps=ordered
    );
}
