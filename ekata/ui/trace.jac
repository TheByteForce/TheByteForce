"""Agent activity: plain-language rows (time, agent, what it did, why, referee outcome).

TraceStrip stays for the desk; AgentActivity is the district tab.
"""

import from "react" { useEffect }
import type from ekata.views { TraceRow }
import from ekata.api { trace_since }
import from .atoms { Empty, RefereeBadge, pretty }

def:pub agent_group(agent: str) -> str {
    if agent in ["ranker", "priority", "call_brief"] { return "ranker"; }
    if agent in ["referee", "referee_merge", "referee_merge_retry", "appeal_referee"] { return "referee"; }
    if agent == "blocking" { return "resolver"; }
    if agent in ["intake", "resolver", "matcher", "officer", "ngo"] { return agent; }
    return "other";
}

def:pub agent_name(agent: str) -> str {
    names = {
        "intake": "Intake agent",
        "blocking": "Candidate finder",
        "resolver": "Resolver agent",
        "ranker": "Ranking agent",
        "priority": "Ranking agent",
        "call_brief": "Call brief agent",
        "matcher": "Matching agent",
        "referee": "Referee",
        "referee_merge": "Referee",
        "referee_merge_retry": "Referee",
        "appeal_referee": "Appeal referee",
        "appeal_investigator": "Appeal investigator",
        "officer": "Divisional officer",
        "ngo": "Relief group",
        "desk": "Call desk",
        "analyst": "Analyst",
        "district": "District office",
        "freshness": "Freshness check"
    };
    return names.get(agent, pretty(agent));
}

def:pub trace_seq(r: TraceRow) -> int {
    return r.seq;
}

def:pub merge_rows(existing: list[TraceRow], incoming: list[TraceRow]) -> list[TraceRow] {
    seen: list[int] = [];
    out: list[TraceRow] = [];
    for r in incoming + existing {
        if r.seq not in seen {
            seen = seen + [r.seq];
            out = out + [r];
        }
    }
    return sorted(out, key=trace_seq, reverse=True)[:300];
}

def:pub top_seq(rows: list[TraceRow]) -> int {
    top: int = 0;
    for r in rows {
        if r.seq > top { top = r.seq; }
    }
    return top;
}

def:pub TraceItem(r: TraceRow) -> JsxElement {
    <li className="border-b border-border px-4 py-2.5 text-[15px] last:border-b-0">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span className="w-12 shrink-0 text-[13px] tabular-nums text-muted-foreground">
                {r.storm_time}
            </span>
            <span className="font-semibold">{agent_name(r.agent)}</span>
            <span>{pretty(r.action)}</span>
            {if r.target != "" {
                <span className="text-[13px] text-muted-foreground">{"on " + r.target}</span>
            }}
            {if r.outcome != "" {
                <span className="ml-auto"><RefereeBadge outcome={r.outcome}/></span>
            }}
        </div>
        {if r.reason != "" {
            <p className="mt-1 pl-[60px] text-[13px] text-muted-foreground">{r.reason}</p>
        }}
    </li>
}

def:pub TraceStrip(
    rows: list[TraceRow], knownIds: list[str], onSelect: Callable[[str], None]
) -> JsxElement {
    <section
        aria-label="Agent trace"
        className="flex min-h-0 flex-col border-t border-border bg-card lg:h-40 lg:shrink-0"
    >
        <div
            className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-2 lg:px-6"
        >
            <h2 className="text-[17px] font-semibold">Agent activity</h2>
            <a
                href="/graph"
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-md border border-border px-3 py-1 text-[13px] font-semibold hover:bg-muted focus-visible:outline-2 focus-visible:outline-primary"
            >
                Open live graph
            </a>
        </div>
        <div className="max-h-72 min-h-0 flex-1 overflow-y-auto lg:max-h-none">
            {if len(rows) == 0 {
                <p className="p-4 text-[15px] text-muted-foreground">
                    No agent decisions yet. Every merge, check and block will be listed here.
                </p>
            }}
            <ol>
                {for r in rows {
                    <TraceItem key={str(r.seq)} r={r}/>
                }}
            </ol>
        </div>
    </section>
}

def:pub AgentActivity -> JsxElement {
    has rows: list[TraceRow] = [];
    has group: str = "all";
    has error: str = "";
    has loaded: bool = False;
    has cursor: int = 0;

    async def poll -> None {
        try {
            fresh = await trace_since(cursor);
            if len(fresh) > 0 {
                rows = merge_rows(rows, fresh);
                cursor = top_seq(rows);
            }
            error = "";
        } except Exception as e {
            error = "Could not load agent activity. It will retry.";
        }
        loaded = True;
    }
    async can with entry {
        await poll();
    }
    useEffect(
        lambda {
            timer = setInterval(lambda { poll(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        [cursor]
    );

    groups = [
        ["all", "All"], ["intake", "Intake"], ["resolver", "Resolver"], ["ranker", "Ranking"],
        ["matcher", "Matching"], ["referee", "Referee"], ["officer", "Officer"], ["ngo", "Relief groups"]
    ];
    shown = rows if group == "all" else [r for r in rows if agent_group(r.agent) == group];

    <section aria-label="Agent activity">
        <div className="mb-3 flex flex-wrap items-center gap-2">
            {for g in groups {
                <button
                    key={g[0]}
                    type="button"
                    aria-pressed={group == g[0]}
                    className={"rounded-full border px-3 py-1 text-[13px] font-semibold focus-visible:outline-2 focus-visible:outline-primary "
                        + ("border-primary bg-primary text-primary-foreground" if group == g[0] else "border-border bg-card hover:bg-muted")}
                    onClick={lambda (e: MouseEvent) { group = g[0]; }}
                >
                    {g[1]}
                </button>
            }}
            <a
                href="/graph"
                target="_blank"
                rel="noopener noreferrer"
                className="ml-auto text-[13px] font-semibold text-primary underline-offset-2 hover:underline"
            >
                Open live graph
            </a>
        </div>
        {if error != "" {
            <p role="alert" className="mb-3 text-[13px] text-blocked">{error}</p>
        }}
        {if loaded and len(shown) == 0 {
            <Empty title="No agent activity yet" hint="Every merge, check and routing decision will be listed here."/>
        }}
        {if len(shown) > 0 {
            <ol className="rounded-lg border border-border bg-card">
                {for r in shown {
                    <TraceItem key={str(r.seq)} r={r}/>
                }}
            </ol>
        }}
    </section>
}
