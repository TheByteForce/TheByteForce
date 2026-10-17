"""An incident call brief, stored only after explicit generation."""
import os;
import from crisisconnect.schema { CrisisConnectHub, Incident, Holds }
import from crisisconnect.store { messages_of, open_pending, log_decision }
import from crisisconnect.ai.models { fast, last_model }

glob brief_model: any = fast;

obj CallBrief {
    has known: list[str] = [];
    has missing: list[str] = [];
    has contradictions: list[str] = [];
    has questions: list[str] = [];
    has model: str = "rules";
}
node BriefRecord {
    has inc_id: str;
    has known: list[str] = [];
    has missing: list[str] = [];
    has contradictions: list[str] = [];
    has questions: list[str] = [];
    has model: str = "rules";
    has version: int = 0;
}

def compose_brief(facts: list[str], timeline: list[str], conflicts: list[str]) -> CallBrief by brief_model(
    temperature=0.0, incl_info={"policy": "Summarize only the cited facts. Separate known, missing and contradictory information. Return exactly THREE concise questions for the volunteer's one verification call. Never assume rescued or verified without a human call log."}
);

def baseline_brief(hub: CrisisConnectHub, inc: Incident) -> CallBrief {
    known = [inc.summary, "Location: " + inc.place, "People: " + str(inc.headcount), "Flags: " + ", ".join(inc.vulnerable)];
    missing: list[str] = [];
    if inc.place == "" { missing.append("Exact household location"); }
    if inc.headcount == 0 { missing.append("Current headcount"); }
    conflicts = [p.fld + ": " + p.old_value + " vs " + p.new_value + " [" + p.msg_id + "]" for p in open_pending(hub, inc.inc_id)];
    return CallBrief(known=known, missing=missing, contradictions=conflicts, questions=["Where exactly are you, and is the water still rising?", "How many people are there, and does anyone need urgent medical or mobility assistance?", "Have you been reached or rescued, and what help do you need now?"]);
}

def read_brief(hub: CrisisConnectHub, inc: Incident) -> CallBrief {
    for b in [hub ->:Holds:->[?:BriefRecord, inc_id == inc.inc_id]] {
        if b.version == len(messages_of(inc)) {
            return CallBrief(known=b.known, missing=b.missing, contradictions=b.contradictions, questions=b.questions, model=b.model);
        }
    }
    return baseline_brief(hub, inc);
}

def generate_brief(hub: CrisisConnectHub, inc: Incident) -> CallBrief {
    result = baseline_brief(hub, inc);
    if os.environ.get("CRISISCONNECT_AI", "on") != "off" {
        try {
            candidate = compose_brief(result.known, [m.msg_id + ": " + m.text for m in messages_of(inc)], result.contradictions);
            if len(candidate.questions) == 3 { result = candidate; result.model = last_model() or "fast model pool"; }
        } except Exception { result = baseline_brief(hub, inc); }
    }
    for old in [hub ->:Holds:->[?:BriefRecord, inc_id == inc.inc_id]] { del old; }
    hub +>:Holds:+> BriefRecord(inc_id=inc.inc_id, known=result.known, missing=result.missing, contradictions=result.contradictions, questions=result.questions, model=result.model, version=len(messages_of(inc)));
    log_decision(hub, "call_brief", "prepare", "Prepared three verification questions from the incident timeline", "APPLIED", hub.storm_time, [inc], model=result.model, target_label=inc.inc_id);
    return result;
}
