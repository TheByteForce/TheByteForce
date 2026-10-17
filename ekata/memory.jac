"""Ekata agent memory: read-only views derived from Decision nodes (rule R14: no writes).

  agent_run_in      the ordered steps every agent took on one message
  rule_stats_in     how often each referee rule R1..R14 fired, by outcome
  precedents_in     what the desk approved or rejected, grouped by match pattern
  desk_precedents   one-line precedent summary (an LLM tool, counts only)

Everything is recomputed from the graph on each call; no counters are stored.
"""

import re;
import time;
import from ekata.schema { EkataHub, Holds, Message, Decision, About, Candidate, Incident }
import from ekata.store { get_hub, find_message, all_proposals, MergeProposal }
import from ekata.ai.models { call_log, agent_steps }

# ---------- Memory nodes and edges ----------

node MemoryHub { has name: str = "ekata-memory"; }

node AgentRun {
    has run_id: str = "";
    has msg_id: str = "";
    has lane: str = "";
    has mode: str = "RULES";
    has started: str = "";
    has wall_ms: int = 0;
    has llm_calls: int = 0;
    has tokens: int = 0;
    has cost_usd: float = 0.0;
    has outcome: str = "";
}

node LlmCall {
    has caller: str = "";
    has model: str = "";
    has latency_ms: float = 0.0;
    has tokens: int = 0;
    has status: str = "";
    has error: str = "";
}

node ToolCall {
    has tool: str = "";
    has result_preview: str = "";
    has iteration: int = 0;
    has tokens: int = 0;
    has cost_usd: float = 0.0;
}

node Rule {
    has rule_id: str = "";
    has lane: str = "";
    has text: str = "";
}

node Feedback {
    has actor: str = "";
    has action: str = "";
    has pattern: str = "";
    has storm_time: str = "";
}

node UsageAnchor { has name: str = "ekata-memory-usage"; }

node UsageLedger {
    has live_calls: int = 0;
    has cached_calls: int = 0;
    has rule_runs: int = 0;
    has tokens: int = 0;
    has cost_usd: float = 0.0;
    has since: str = "";
}

edge Remembers: MemoryHub --> any {}
edge Handled: AgentRun --> Message {}
edge Step: AgentRun --> Decision { has order: int = 0; }
edge Next: Decision --> Decision {}
edge Called: AgentRun --> LlmCall {}
edge Used: AgentRun --> ToolCall {}
edge Cites: Decision --> Rule {}
edge On: Feedback --> MergeProposal {}
edge Keeps: UsageAnchor --> UsageLedger {}

glob RULE_TEXTS: list[list[str]] = [
    ["R1", "merge", "auto-merge only on exact phone or full name + household place"],
    ["R2", "merge", "a blocked proposal gets one retry"],
    ["R3", "ranking", "vulnerable incidents never ranked below the deterministic score"],
    ["R4", "status", "CONFIRMED/RESOLVED need a logged call"],
    ["R5", "claim", "one desk per incident"],
    ["R6", "verify", "contradictions re-open verification"],
    ["R7", "rumour", "rumours never enter the call queue"],
    ["R8", "appeal", "LIKELY_SCAM needs a signal plus independent evidence"],
    ["R9", "appeal", "MATCHED needs a confirmed incident and an official channel"],
    ["R10", "appeal", "analyst approves public verdicts"],
    ["R11", "appeal", "warnings need a native-speaker check"],
    ["R12", "data", "no real names or offices in data"],
    ["R13", "audit", "every change has a Decision"],
    ["R14", "tools", "tools are read-only; one writer"]
];

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
    has run_id: str = "";
    has mode: str = "";
    has wall_ms: int = 0;
    has llm_calls: int = 0;
    has tokens: int = 0;
    has cost_usd: float = 0.0;
    has call_models: list[str] = [];
}

obj LedgerView {
    has live_calls: int = 0;
    has cached_calls: int = 0;
    has rule_runs: int = 0;
    has tokens: int = 0;
    has cost_usd: float = 0.0;
    has since: str = "";
}

obj RuleCount {
    has rule: str = "";
    has lane: str = "";
    has text: str = "";
    has cites: int = 0;
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

def agent_run_in(hub: EkataHub, msg_id: str, mem_name: str = "ekata-memory") -> AgentRunView {
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
    mh = find_memory_hub(mem_name);
    if mh is not None {
        wanted = msg_id;
        runs = [mh ->:Remembers:->[?:AgentRun, msg_id == wanted]];
        if len(runs) > 0 {
            run = runs[0];
            view.run_id = run.run_id;
            view.mode = run.mode;
            view.wall_ms = run.wall_ms;
            view.llm_calls = run.llm_calls;
            view.tokens = run.tokens;
            view.cost_usd = run.cost_usd;
            for c in [run ->:Called:->[?:LlmCall]] {
                if c.model != "" and c.model not in view.call_models {
                    view.call_models.append(c.model);
                }
            }
        }
    }
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

# ---------- Memory hub, rules, ledger ----------

def find_memory_hub(mem_name: str) -> MemoryHub | None {
    hubs = [root.shared -->][?:MemoryHub, name == mem_name];
    if len(hubs) > 0 {
        return hubs[0];
    }
    return None;
}

def ensure_rules(mh: MemoryHub) {
    if len([mh ->:Remembers:->[?:Rule]]) > 0 {
        return;
    }
    for row in RULE_TEXTS {
        mh +>:Remembers:+> Rule(rule_id=row[0], lane=row[1], text=row[2]);
    }
}

def get_memory_hub(mem_name: str = "ekata-memory") -> MemoryHub {
    found = find_memory_hub(mem_name);
    if found is not None {
        ensure_rules(found);
        return found;
    }
    created = root.shared ++> MemoryHub(name=mem_name);
    ensure_rules(created);
    return created;
}

def get_ledger(mem_name: str) -> UsageLedger {
    anchor_name = mem_name + "-usage";
    anchors = [root.shared -->][?:UsageAnchor, name == anchor_name];
    anchor: UsageAnchor | None = None;
    if len(anchors) > 0 {
        anchor = anchors[0];
    } else {
        anchor = root.shared ++> UsageAnchor(name=anchor_name);
    }
    ledgers = [anchor ->:Keeps:->[?:UsageLedger]];
    if len(ledgers) > 0 {
        return ledgers[0];
    }
    fresh = UsageLedger(since=time.strftime("%Y-%m-%d %H:%M:%S"));
    anchor +>:Keeps:+> fresh;
    return fresh;
}

def usage_ledger_in(mem_name: str = "ekata-memory") -> LedgerView {
    led = get_ledger(mem_name);
    return LedgerView(
        live_calls=led.live_calls, cached_calls=led.cached_calls, rule_runs=led.rule_runs,
        tokens=led.tokens, cost_usd=led.cost_usd, since=led.since
    );
}

def rule_citations_in(mem_name: str = "ekata-memory") -> list[RuleCount] {
    out: list[RuleCount] = [];
    mh = find_memory_hub(mem_name);
    if mh is None {
        return out;
    }
    rows: dict[str, RuleCount] = {};
    for r in [mh ->:Remembers:->[?:Rule]] {
        rows[r.rule_id] = RuleCount(
            rule=r.rule_id, lane=r.lane, text=r.text, cites=len([r <-:Cites:<-[?:Decision]])
        );
    }
    for rid in RULE_IDS {
        if rid in rows {
            out.append(rows[rid]);
        }
    }
    return out;
}

# ---------- Write path (single writer) ----------

def memory_mark() -> dict[str, any] {
    return {"calls": len(call_log), "steps": len(agent_steps), "t": int(time.time() * 1000)};
}

def mode_of(models: list[str]) -> str {
    for m in models {
        if m.startswith("cached:") {
            return "CACHED";
        }
    }
    for m in models {
        if m not in NON_LLM_MODELS {
            return "LIVE";
        }
    }
    return "RULES";
}

def materialise_feedback(hub: EkataHub, mh: MemoryHub) {
    for d in [hub ->:Holds:->[?:Decision]] {
        if d.action != "merge_approved" and d.action != "merge_rejected" {
            continue;
        }
        verdict = "APPROVED" if d.action == "merge_approved" else "REJECTED";
        for p in [d ->:About:->[?:MergeProposal]] {
            seen = False;
            for f in [p <-:On:<-[?:Feedback]] {
                if f.action == verdict {
                    seen = True;
                }
            }
            if seen {
                continue;
            }
            fb = Feedback(
                actor=p.decided_by, action=verdict, pattern=proposal_pattern(hub, p),
                storm_time=d.storm_time
            );
            mh +>:Remembers:+> fb;
            fb +>:On:+> p;
        }
    }
}

def record_run(
    hub: EkataHub, msg: Message, mark: dict[str, any], mem_name: str = "ekata-memory"
) -> AgentRun {
    try {
        mh = get_memory_hub(mem_name);
        wanted = msg.msg_id;
        existing = [mh ->:Remembers:->[?:AgentRun, msg_id == wanted]];
        if len(existing) > 0 {
            return existing[0];
        }
        runs_so_far = len([mh ->:Remembers:->[?:AgentRun]]);
        ds = sorted(
            [msg <-:About:<-[?:Decision]],
            key=lambda (d: Decision) { d.seq; }
        );
        models: list[str] = [d.model for d in ds];
        mode = mode_of(models);
        last_rule_outcome = "";
        last_outcome = "";
        for d in ds {
            last_outcome = d.outcome;
            if rule_of(d.reason) != "" {
                last_rule_outcome = d.outcome;
            }
        }
        c0 = min(int(mark.get("calls", 0)), len(call_log));
        s0 = min(int(mark.get("steps", 0)), len(agent_steps));
        calls = list(call_log[c0:]);
        steps = list(agent_steps[s0:]);
        tokens = 0;
        cost = 0.0;
        for row in calls {
            tokens += int(row.get("total_tokens", 0));
            cost += float(row.get("cost", 0.0));
        }
        t0 = int(mark.get("t", 0));
        wall = max(0, int(time.time() * 1000) - t0) if t0 > 0 else 0;
        run = AgentRun(
            run_id=f"RUN-{(runs_so_far + 1):03d}", msg_id=msg.msg_id, lane=msg.kind,
            mode=mode, started=msg.storm_time, wall_ms=wall, llm_calls=len(calls),
            tokens=tokens, cost_usd=cost,
            outcome=last_rule_outcome if last_rule_outcome != "" else last_outcome
        );
        mh +>:Remembers:+> run;
        run +>:Handled:+> msg;
        rules: dict[str, Rule] = {};
        for r in [mh ->:Remembers:->[?:Rule]] {
            rules[r.rule_id] = r;
        }
        prev: Decision | None = None;
        i = 0;
        for d in ds {
            i += 1;
            run +>:Step(order=i):+> d;
            if prev is not None {
                prev +>:Next:+> d;
            }
            prev = d;
            rid = rule_of(d.reason);
            if rid in rules {
                d +>:Cites:+> rules[rid];
            }
        }
        for row in calls {
            lc = LlmCall(
                caller=str(row.get("caller", "")), model=str(row.get("model", "")),
                latency_ms=float(row.get("latency_ms", 0.0)),
                tokens=int(row.get("total_tokens", 0)), status=str(row.get("status", "")),
                error=str(row.get("error", ""))
            );
            mh +>:Remembers:+> lc;
            run +>:Called:+> lc;
        }
        for row in steps {
            tc = ToolCall(
                tool=str(row.get("tool", "")),
                result_preview=str(row.get("result_preview", "")),
                iteration=int(row.get("iteration", 0)),
                tokens=int(row.get("tokens", 0)), cost_usd=float(row.get("cost", 0.0))
            );
            mh +>:Remembers:+> tc;
            run +>:Used:+> tc;
        }
        materialise_feedback(hub, mh);
        led = get_ledger(mem_name);
        led.live_calls += len(calls);
        led.cached_calls += len([m for m in models if m.startswith("cached:")]);
        if mode == "RULES" {
            led.rule_runs += 1;
        }
        led.tokens += tokens;
        led.cost_usd += cost;
        return run;
    } except Exception as e {
        return AgentRun(msg_id=msg.msg_id, lane=msg.kind, outcome="FAILED");
    }
}

def reset_memory(mem_name: str = "ekata-memory") {
    mh = get_memory_hub(mem_name);
    for n in [mh ->:Remembers:->] {
        del n;
    }
    ensure_rules(mh);
}
