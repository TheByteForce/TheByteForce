"""Alert levels: a five-level call urgency for every open incident."""

import from "@jac/runtime" { Link }
import from "@hugeicons/core-free-icons" { Alert02Icon }
import type from ekata.alert_level { AlertRow }
import from ekata.coordination_api { alert_levels, set_alert_override }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.native_select { NativeSelectOption }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { LevelTag }
import from ...components.app.labels { plural }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, SelectField }

glob LEVEL_GUIDE: list[list[str]] = [
    ["5", "Life at risk now", "Call immediately"],
    ["4", "Rescue needed", "Call next"],
    ["3", "Vulnerable first", "Call before others"],
    ["2", "Verify or confirm", "Call when free"],
    ["1", "Closed", "No call needed"]
];

def:pub count_level(rows: list[AlertRow], level: int) -> int {
    return len([a for a in rows if a.level == level]);
}

def:pub AlertsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[AlertRow] = [];
    has loaded: bool = False;
    has pick: str = "";
    has level: str = "5";
    has reason: str = "";
    has saving: bool = False;
    has notice: str = "";
    has err: str = "";

    async def apply_override -> None {
        if pick == "" or reason.strip() == "" or saving {
            return;
        }
        saving = True;
        err = "";
        notice = "";
        try {
            rows = await set_alert_override(pick, int(level), reason.strip(), "District desk");
            notice = f"{pick} set to level {level}.";
            reason = "";
            ctx.bump();
        } except Exception as ex {
            err = str(ex);
        }
        saving = False;
    }

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
        <PageHero
            eyebrow="District · Alert levels"
            title="How soon each case needs a call."
            description="Every open case gets a level from 1 to 5. Levels come from fixed rules, not from a model, so the same facts always give the same level."
            image="/static/assets/images/satellite.jpg"
            imageAlt="Satellite view of flooding across Sri Lanka"
            capsules={[
                [f"{count_level(rows, 5)} life at risk", "red"],
                [f"{count_level(rows, 4)} rescue needed", "orange"],
                [f"{count_level(rows, 3)} vulnerable first", "amber"],
                [f"{count_level(rows, 2)} to verify", "blue"]
            ]}
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
                <CardTitle>Change a level</CardTitle>
                <CardDescription>When the district knows something the rules do not. Every change is logged with your reason.</CardDescription>
            </CardHeader>
            <CardContent>
                <form className="flex flex-wrap items-end gap-4" onSubmit={lambda (e: FormEvent) { e.preventDefault(); apply_override(); }}>
                    <div className="flex flex-col gap-2">
                        <label htmlFor="ov-case" className="text-sm font-medium">Case</label>
                        <SelectField id="ov-case" value={pick} className="w-40" onChange={lambda (e: ChangeEvent) { pick = e.target.value; }}>
                            <NativeSelectOption value="">Choose</NativeSelectOption>
                            {for a in rows {
                                <NativeSelectOption key={a.inc_id} value={a.inc_id}>{a.inc_id}</NativeSelectOption>
                            }}
                        </SelectField>
                    </div>
                    <div className="flex flex-col gap-2">
                        <label htmlFor="ov-level" className="text-sm font-medium">New level</label>
                        <SelectField id="ov-level" value={level} className="w-28" onChange={lambda (e: ChangeEvent) { level = e.target.value; }}>
                            {for g in LEVEL_GUIDE {
                                <NativeSelectOption key={g[0]} value={g[0]}>{"Level " + g[0]}</NativeSelectOption>
                            }}
                        </SelectField>
                    </div>
                    <div className="flex min-w-56 flex-1 flex-col gap-2">
                        <label htmlFor="ov-reason" className="text-sm font-medium">Reason</label>
                        <Input id="ov-reason" value={reason} placeholder="Example: river gauge shows the road is cut" onChange={lambda (e: ChangeEvent) { reason = e.target.value; }} />
                    </div>
                    <Button type="submit" className="rounded-full pl-4 pr-4" disabled={saving or pick == "" or reason.strip() == ""}>
                        {"Saving..." if saving else "Change level"}
                    </Button>
                </form>
                {if notice != "" {
                    <p role="status" className="mt-4 text-sm text-emerald-700">{notice}</p>
                }}
                {if err != "" {
                    <Alert variant="destructive" className="mt-4">
                        <AlertDescription>{err}</AlertDescription>
                    </Alert>
                }}
            </CardContent>
        </Card>

        <Card>
            <CardHeader>
                <CardTitle>Alert board</CardTitle>
                <CardDescription>{plural(len(rows), "open case", "open cases") + ", highest level first."}</CardDescription>
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
                                        <Link to={"/officer/cases/" + a.inc_id} className="font-mono text-sm font-medium text-primary underline-offset-4 hover:underline">
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
