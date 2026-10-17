"""Alert levels: a five-level call urgency for every open incident."""

import from "@jac/runtime" { Link }
import from "@hugeicons/core-free-icons" { Alert02Icon }
import type from ekata.alert_level { AlertRow }
import from ekata.coordination_api { alert_levels }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ..components.app.desk_state { use_desk }
import from ..components.app.tags { LevelTag }
import from ..components.app.labels { plural }
import from ..components.app.page_parts { PageHeader, EmptyNote, LoadingRows }

glob LEVEL_GUIDE: list[list[str]] = [
    ["5", "Life at risk now", "Call immediately"],
    ["4", "Rescue needed", "Call next"],
    ["3", "Vulnerable first", "Call before others"],
    ["2", "Verify or confirm", "Call when free"],
    ["1", "Closed", "No call needed"]
];

def:pub AlertsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[AlertRow] = [];
    has loaded: bool = False;

    async def load(t: int) -> None {
        try {
            rows = await alert_levels(t);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    async can with [ctx.tick] entry {
        await load(ctx.tick);
    }

    <div className="flex flex-col gap-6">
        <PageHeader
            title="Alert levels"
            description="Each open incident gets a level from 1 to 5 that says how soon it needs a call. Levels are set by fixed rules, not by a model."
            image="/static/assets/images/satellite.jpg"
            imageAlt="Satellite view of flooding across Sri Lanka"
        />

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
            {for g in LEVEL_GUIDE {
                <div key={g[0]} className="rounded-lg border bg-card pt-3 pb-3 pl-3 pr-3">
                    <LevelTag level={int(g[0])} />
                    <p className="mt-2 text-sm font-medium">{g[1]}</p>
                    <p className="text-xs text-muted-foreground">{g[2]}</p>
                </div>
            }}
        </div>

        <Card>
            <CardHeader>
                <CardTitle>Alert board</CardTitle>
                <CardDescription>{plural(len(rows), "open incident", "open incidents") + ", highest level first."}</CardDescription>
            </CardHeader>
            <CardContent>
                {if not loaded {
                    <LoadingRows count={4} className="h-10" />
                } elif len(rows) == 0 {
                    <EmptyNote
                        title="No open incidents"
                        description="Alert levels appear once messages arrive."
                        icon={Alert02Icon}
                    />
                } else {
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Level</TableHead>
                                <TableHead>Incident</TableHead>
                                <TableHead>Action</TableHead>
                                <TableHead>Reason</TableHead>
                                <TableHead className="text-right">Priority</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {for a in rows {
                                <TableRow key={a.inc_id}>
                                    <TableCell><LevelTag level={a.level} /></TableCell>
                                    <TableCell>
                                        <Link to={"/incidents/" + a.inc_id} className="font-mono text-sm font-medium text-primary underline-offset-4 hover:underline">
                                            {a.inc_id}
                                        </Link>
                                    </TableCell>
                                    <TableCell className="font-medium">{a.action}</TableCell>
                                    <TableCell className="whitespace-normal text-muted-foreground">{a.reason}</TableCell>
                                    <TableCell className="text-right tabular-nums">{f"{a.priority:.1f}"}</TableCell>
                                </TableRow>
                            }}
                        </TableBody>
                    </Table>
                }}
            </CardContent>
        </Card>
    </div>
}
