"""Agent activity: every decision the agents made and what the referee allowed."""

import from "@hugeicons/core-free-icons" { Activity01Icon }
import type from ekata.views { TraceRow }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.tabs { Tabs, TabsList, TabsTrigger }
import from ...components.app.desk_state { use_desk }
import from ...components.app.items { TraceItem, fetch_trace }
import from ...components.app.labels { plural, agent_group }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows }

glob AGENT_FILTERS: list[list[str]] = [
    ["all", "All"], ["intake", "Intake"], ["resolver", "Resolver"], ["ranker", "Ranking"],
    ["matcher", "Matching"], ["referee", "Referee"], ["officer", "Officer"], ["ngo", "Relief groups"]
];

def:pub count_outcome(rows: list[TraceRow], outcome: str) -> int {
    return len([r for r in rows if r.outcome == outcome]);
}

def:pub ActivityPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[TraceRow] = [];
    has loaded: bool = False;
    has agent: str = "all";

    async def load(t: int) -> None {
        try {
            rows = await fetch_trace(0, t);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    async can with [ctx.tick] entry {
        await load(ctx.tick);
    }

    newest: list[TraceRow] = list(reversed(rows));
    shown: list[TraceRow] = newest if agent == "all" else [r for r in newest if agent_group(r.agent) == agent];

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District · Agent activity"
            title="Every decision, explained."
            description="Each step the pipeline took, newest first: which agent acted, why, and whether the referee applied it, blocked it or sent it to a person."
            image="/static/assets/images/desk-operators.jpg"
            imageAlt="Duty officers working at screens in an operations centre"
            capsules={[
                [plural(len(rows), "decision", "decisions"), "blue"],
                [f"{count_outcome(rows, 'APPLIED')} applied", "green"],
                [f"{count_outcome(rows, 'NEEDS_HUMAN')} need a person", "amber"],
                [f"{count_outcome(rows, 'BLOCKED')} blocked", "red"]
            ]}
        />
        <Card>
            <CardHeader>
                <CardTitle>Decision log</CardTitle>
                <CardDescription>{plural(len(shown), "decision", "decisions")}</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
                <Tabs value={agent} onValueChange={lambda (v: str) { agent = v; }}>
                    <TabsList className="h-auto flex-wrap rounded-full pt-1 pb-1 pl-1 pr-1">
                        {for f in AGENT_FILTERS {
                            <TabsTrigger key={f[0]} value={f[0]} className="rounded-full pl-3 pr-3">{f[1]}</TabsTrigger>
                        }}
                    </TabsList>
                </Tabs>
                {if not loaded {
                    <LoadingRows count={5} className="h-12" />
                } elif len(shown) == 0 {
                    <EmptyNote
                        title="No decisions yet"
                        description="Every merge, check and block is listed here as messages are processed."
                        icon={Activity01Icon}
                    />
                } else {
                    <ol>
                        {for r in shown[:200] {
                            <TraceItem key={str(r.seq)} r={r} />
                        }}
                    </ol>
                }}
            </CardContent>
        </Card>
    </div>
}
