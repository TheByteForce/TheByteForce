"""Agent activity: every decision the agents made and what the referee allowed."""

import from "@hugeicons/core-free-icons" { Activity01Icon }
import type from ekata.views { TraceRow }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.tabs { Tabs, TabsList, TabsTrigger }
import from ..components.app.desk_state { use_desk }
import from ..components.app.items { TraceItem, fetch_trace }
import from ..components.app.labels { plural }
import from ..components.app.page_parts { PageHeader, EmptyNote, LoadingRows }

glob AGENT_FILTERS: list[list[str]] = [
    ["all", "All"], ["intake", "Intake"], ["blocking", "Blocking"], ["referee", "Referee"],
    ["freshness", "Freshness"], ["priority", "Priority"]
];

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
    shown: list[TraceRow] = newest if agent == "all" else [r for r in newest if r.agent == agent];

    <div className="flex flex-col gap-6">
        <PageHeader
            title="Agent activity"
            description="Every step the pipeline took, newest first: which agent acted, why, and whether the referee applied it, blocked it or sent it to a person."
        />
        <Card>
            <CardHeader>
                <CardTitle>Decision log</CardTitle>
                <CardDescription>{plural(len(shown), "decision", "decisions")}</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
                <Tabs value={agent} onValueChange={lambda (v: str) { agent = v; }}>
                    <TabsList>
                        {for f in AGENT_FILTERS {
                            <TabsTrigger key={f[0]} value={f[0]}>{f[1]}</TabsTrigger>
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
