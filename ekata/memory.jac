"""Ekata agent memory: read-only views derived from Decision nodes (rule R14: no writes).

  agent_run_in      the ordered steps every agent took on one message
  rule_stats_in     how often each referee rule R1..R14 fired, by outcome
  precedents_in     what the desk approved or rejected, grouped by match pattern
  desk_precedents   one-line precedent summary (an LLM tool, counts only)

Everything is recomputed from the graph on each call; no counters are stored.
"""

import re;
import from ekata.schema { EkataHub, Holds, Message, Decision, About, Candidate, Incident }
import from ekata.store { get_hub, find_message, all_proposals, MergeProposal }

glob RULE_IDS: list[str] = [
    "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10", "R11", "R12", "R13", "R14"
];
glob NON_LLM_MODELS: list[str] = ["rules", "human", ""];

obj RunStep {
    has seq: int = 0;
    has agent: str = "";
    has action: str = "";
    has rule: str = "";
    has outcome: str = "";
    has model: str = "";
    has confidence: float = 0.0;
    has reason: str = "";
    has target: str = "";
    has storm_time: str = "";
}

obj AgentRunView {
    has msg_id: str = "";
    has found: bool = False;
    has steps: list[RunStep] = [];
    has agents: list[str] = [];
    has models: list[str] = [];
    has llm_steps: int = 0;
    has rule_steps: int = 0;
    has blocked: int = 0;
    has retries: int = 0;
    has outcome: str = "";
}

obj RuleStat {
    has rule: str = "";
    has applied: int = 0;
    has blocked: int = 0;
    has needs_human: int = 0;
    has new_incident: int = 0;
    has total: int = 0;
}

obj Precedent {
    has pattern: str = "";
    has approved: int = 0;
    has rejected: int = 0;
    has ids: list[str] = [];
}

def rule_of(reason: str) -> str {
    m = re.match(r"^(R\d{1,2})\b", reason);
    if m {
        return m.group(1);
    }
    return "";
}

def agent_run_in(hub: EkataHub, msg_id: str) -> AgentRunView {
    view = AgentRunView(msg_id=msg_id);
    msg = find_message(hub, msg_id);
    if msg is None {
        return view;
    }
    view.found = True;
    ds = sorted(
        [msg <-:About:<-[?:Decision]],
        key=lambda (d: Decision) { d.seq; }
    );
    last_rule_outcome = "";
    last_outcome = "";
    for d in ds {
        r = rule_of(d.reason);
        view.steps.append(RunStep(
            seq=d.seq, agent=d.agent, action=d.action, rule=r, outcome=d.outcome,
            model=d.model, confidence=d.confidence, reason=d.reason,
            target=d.target, storm_time=d.storm_time
        ));
        if d.agent not in view.agents {
            view.agents.append(d.agent);
        }
        if d.model not in NON_LLM_MODELS {
            view.llm_steps += 1;
            if d.model not in view.models {
                view.models.append(d.model);
            }
        } else {
            view.rule_steps += 1;
        }
        if d.outcome == "BLOCKED" {
            view.blocked += 1;
        }
        if d.action.endswith("_retry") {
            view.retries += 1;
        }
        last_outcome = d.outcome;
        if r != "" {
            last_rule_outcome = d.outcome;
        }
    }
    view.outcome = last_rule_outcome if last_rule_outcome != "" else last_outcome;
    return view;
}

def rule_stats_in(hub: EkataHub) -> list[RuleStat] {
    rows: dict[str, RuleStat] = {};
    out: list[RuleStat] = [];
    for rid in RULE_IDS {
        row = RuleStat(rule=rid);
        rows[rid] = row;
        out.append(row);
    }
    for d in [hub ->:Holds:->[?:Decision]] {
        r = rule_of(d.reason);
        if r not in rows {
            continue;
        }
        row = rows[r];
        row.total += 1;
        if d.outcome == "APPLIED" {
            row.applied += 1;
        } elif d.outcome == "BLOCKED" {
            row.blocked += 1;
        } elif d.outcome == "NEEDS_HUMAN" {
            row.needs_human += 1;
        } elif d.outcome == "NEW_INCIDENT" {
            row.new_incident += 1;
        }
    }
    return out;
}

# Match pattern from Candidate reason tags and keywords ("" when nothing fits).
def pattern_for(reasons: list[str]) -> str {
    joined = " | ".join(reasons).lower();
    if "[strong]" in joined {
        if "phone" in joined {
            return "STRONG:phone";
        }
        return "STRONG:name+house";
    }
    if "[medium]" in joined {
        if "full name" in joined {
            return "MEDIUM:name-only";
        }
        return "MEDIUM:house-only";
    }
    if "[weak]" in joined {
        return "WEAK:surname+road";
    }
    return "";
}

def proposal_pattern(hub: EkataHub, p: MergeProposal) -> str {
    msg = find_message(hub, p.msg_id);
    if msg is not None {
        for inc in [msg ->:Candidate:->[?:Incident, inc_id == p.inc_id]] {
            for ed in [edge msg ->:Candidate:-> inc] {
                found = pattern_for(ed.reasons);
                if found != "" {
                    return found;
                }
            }
        }
    }
    return pattern_for([p.reason]);
}

def precedents_in(hub: EkataHub) -> list[Precedent] {
    groups: dict[str, Precedent] = {};
    out: list[Precedent] = [];
    for p in all_proposals(hub) {
        if p.status != "APPROVED" and p.status != "REJECTED" {
            continue;
        }
        pat = proposal_pattern(hub, p);
        if pat == "" {
            pat = "unclassified";
        }
        if pat not in groups {
            fresh = Precedent(pattern=pat);
            groups[pat] = fresh;
            out.append(fresh);
        }
        g = groups[pat];
        if p.status == "APPROVED" {
            g.approved += 1;
        } else {
            g.rejected += 1;
        }
        g.ids.append(f"{p.msg_id}->{p.inc_id}");
    }
    return sorted(out, key=lambda (g: Precedent) { g.pattern; });
}

def desk_precedents_in(hub: EkataHub, pattern: str) -> str {
    for g in precedents_in(hub) {
        if g.pattern == pattern {
            ids = ", ".join(g.ids);
            return (
                f"Tonight the desk REJECTED {g.rejected} and APPROVED {g.approved} "
                + f"merges with pattern {pattern} (MP ids: {ids})"
            );
        }
    }
    return "no precedents yet";
}

"""Tool: what the desk decided on merges with this match pattern tonight (counts only)."""
def desk_precedents(pattern: str) -> str {
    return desk_precedents_in(get_hub(), pattern);
}
