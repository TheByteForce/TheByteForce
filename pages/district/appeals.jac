"""District: appeals and rumours. An analyst approves each verdict before any
warning is published."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Shield01Icon, AiBrain01Icon, CheckmarkCircle01Icon, SecurityCheckIcon, Megaphone01Icon }
import type from ekata.casework { AppealView, RumourView }
import from ekata.case_api { appeals, rumour_log, decide_appeal, investigate_appeal }
import from ekata.coordination_api { run_appeal_checks }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.tabs { Tabs, TabsList, TabsTrigger }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { Tag, VerdictTag }
import from ...components.app.labels { plural, pretty }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }

def:pub count_verdict(rows: list[AppealView], verdict: str) -> int {
    return len([v for v in rows if v.verdict == verdict]);
}

def:pub stance_label(stance: str) -> str {
    if stance == "CONTRADICTED" {
        return "Official sources contradict this";
    }
    if stance == "CONFIRMED" {
        return "Official sources confirm this";
    }
    return "Not confirmed by any official source";
}

def:pub AppealsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[AppealView] = [];
    has rumours: list[RumourView] = [];
    has loaded: bool = False;
    has view: str = "appeals";
    has busy: str = "";
    has notice: str = "";
    has err: str = "";

    async can with [ctx.tick] entry {
        try {
            rows = await appeals(ctx.tick);
            rumours = await rumour_log(ctx.tick);
        } except Exception as ex {
            rows = rows;
        }
        loaded = True;
    }

    async def investigate(appealId: str) -> None {
        if busy != "" {
            return;
        }
        busy = appealId;
        err = "";
        notice = "";
        try {
            await investigate_appeal(appealId);
            notice = "Investigation finished for " + appealId + ".";
            ctx.bump();
        } except Exception as ex {
            err = "The investigation did not finish: " + str(ex);
        }
        busy = "";
    }

    async def decide(appealId: str, approve: bool) -> None {
        if busy != "" {
            return;
        }
        busy = appealId;
        err = "";
        notice = "";
        try {
            await decide_appeal(appealId, ctx.analyst, approve);
            notice = ("Verdict approved for " if approve else "Approval withdrawn for ") + appealId + ".";
            ctx.bump();
        } except Exception as ex {
            err = str(ex);
        }
        busy = "";
    }

    async def check_all -> None {
        if busy != "" {
            return;
        }
        busy = "all";
        try {
            await run_appeal_checks();
            notice = "Every appeal was checked again.";
            ctx.bump();
        } except Exception as ex {
            err = str(ex);
        }
        busy = "";
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District coordination · Appeals and rumours"
            title="Check an appeal before anyone pays."
            description="Fundraising appeals are checked for shared bank accounts, impersonated officials and requests for OTPs or NIC photos. Forwarded warnings are checked against official bulletins."
            image="/static/assets/images/community-check.jpg"
            imageAlt="Response workers speaking with a resident at their door"
            capsules={[
                [f"{count_verdict(rows, 'LIKELY_SCAM')} likely scam", "red"],
                [f"{count_verdict(rows, 'SUSPICIOUS')} suspicious", "orange"],
                [f"{count_verdict(rows, 'MATCHED')} matched", "green"],
                [plural(len(rumours), "rumour", "rumours"), "violet"]
            ]}
        >
            <Button className="rounded-full pl-4 pr-4" disabled={busy != ""} onClick={lambda (e: MouseEvent) { check_all(); }}>
                <HugeiconsIcon icon={SecurityCheckIcon} strokeWidth={2} data-icon="inline-start" />
                {"Checking..." if busy == "all" else "Check every appeal again"}
            </Button>
        </PageHero>

        <Alert>
            <HugeiconsIcon icon={Shield01Icon} strokeWidth={2} />
            <AlertTitle>{"Reviewing as " + ctx.analyst}</AlertTitle>
            <AlertDescription>
                A missing confirmed case is never treated as proof of fraud. Warnings stay drafts until an analyst approves the verdict. Change the analyst in the sidebar.
            </AlertDescription>
        </Alert>
        {if notice != "" {
            <Alert>
                <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} />
                <AlertDescription>{notice}</AlertDescription>
            </Alert>
        }}
        {if err != "" {
            <Alert variant="destructive">
                <AlertDescription>{err}</AlertDescription>
            </Alert>
        }}

        <Tabs value={view} onValueChange={lambda (v: str) { view = v; }}>
            <TabsList className="h-auto rounded-full pt-1 pb-1 pl-1 pr-1">
                <TabsTrigger value="appeals" className="rounded-full pl-3 pr-3">{f"Appeals ({len(rows)})"}</TabsTrigger>
                <TabsTrigger value="rumours" className="rounded-full pl-3 pr-3">{f"Rumours ({len(rumours)})"}</TabsTrigger>
            </TabsList>
        </Tabs>

        {if not loaded {
            <LoadingRows count={3} className="h-32" />
        } elif view == "appeals" and len(rows) == 0 {
            <EmptyNote title="No appeals yet" description="Appeals asking for money or documents appear here with their verdict." icon={Shield01Icon} />
        } elif view == "appeals" {
            <div className="flex flex-col gap-4">
                {for a in rows {
                    <Card key={a.appeal_id}>
                        <CardHeader>
                            <div className="flex flex-wrap items-center gap-2">
                                <CardTitle className="font-mono">{a.appeal_id}</CardTitle>
                                <VerdictTag verdict={a.verdict} />
                                {if a.approved_by != "" {
                                    <Tag label={"Approved by " + a.approved_by} tone="green" />
                                } else {
                                    <Tag label="Waiting for an analyst" tone="amber" />
                                }}
                                <span className="ml-auto text-xs text-muted-foreground">{"Received " + a.storm_time}</span>
                            </div>
                            <CardDescription className="leading-relaxed">{a.text}</CardDescription>
                        </CardHeader>
                        <CardContent className="flex flex-col gap-4">
                            {if a.reason != "" {
                                <p className="text-sm"><span className="font-medium">Why: </span>{a.reason}</p>
                            }}
                            {if len(a.evidence) > 0 {
                                <div>
                                    <p className="text-sm font-medium">Evidence</p>
                                    <ul className="mt-2 flex flex-col gap-1 text-sm text-muted-foreground">
                                        {for ev in a.evidence {
                                            <li key={ev.ref + ev.text}>
                                                <span className="font-mono text-xs">{ev.ref}</span>
                                                {" "}
                                                {ev.text}
                                            </li>
                                        }}
                                    </ul>
                                </div>
                            }}
                            {if a.case_summary != "" {
                                <p className="rounded-lg bg-muted pt-3 pb-3 pl-3 pr-3 text-sm">{a.case_summary}</p>
                            }}
                            {if a.warning_draft != "" {
                                <div className="rounded-lg border border-dashed pt-3 pb-3 pl-3 pr-3 text-sm">
                                    <p className="text-xs font-medium text-muted-foreground">Warning draft, not published</p>
                                    <p className="mt-1">{a.warning_draft}</p>
                                </div>
                            }}
                            <div className="flex flex-wrap gap-2">
                                <Button variant="outline" size="sm" className="rounded-full pl-3 pr-3" disabled={busy != ""} onClick={lambda (e: MouseEvent) { investigate(a.appeal_id); }}>
                                    <HugeiconsIcon icon={AiBrain01Icon} strokeWidth={2} data-icon="inline-start" />
                                    {"Investigating..." if busy == a.appeal_id else "Investigate with AI"}
                                </Button>
                                {if a.approved_by == "" {
                                    <Button size="sm" className="rounded-full pl-3 pr-3" disabled={busy != ""} onClick={lambda (e: MouseEvent) { decide(a.appeal_id, True); }}>
                                        Approve verdict
                                    </Button>
                                } else {
                                    <Button size="sm" variant="outline" className="rounded-full pl-3 pr-3" disabled={busy != ""} onClick={lambda (e: MouseEvent) { decide(a.appeal_id, False); }}>
                                        Withdraw approval
                                    </Button>
                                }}
                            </div>
                        </CardContent>
                    </Card>
                }}
            </div>
        } elif len(rumours) == 0 {
            <EmptyNote title="No rumours logged" description="Forwarded warnings and claims appear here, checked against official bulletins." icon={Megaphone01Icon} />
        } else {
            <div className="flex flex-col gap-4">
                {for r in rumours {
                    <Card key={r.source_id + r.storm_time}>
                        <CardHeader>
                            <div className="flex items-start gap-4">
                                <IconChip icon={Megaphone01Icon} tone={"red" if r.stance == "CONTRADICTED" else ("green" if r.stance == "CONFIRMED" else "slate")} />
                                <div className="flex flex-col gap-1">
                                    <CardTitle className="leading-snug">{r.claim}</CardTitle>
                                    <CardDescription>{stance_label(r.stance) + " · " + r.storm_time}</CardDescription>
                                </div>
                            </div>
                        </CardHeader>
                        {if len(r.bulletins) > 0 {
                            <CardContent>
                                <ul className="flex flex-col gap-2 text-sm">
                                    {for b in r.bulletins {
                                        <li key={b.ref} className="rounded-lg bg-muted pt-2 pb-2 pl-3 pr-3">
                                            <span className="font-medium">{pretty(b.kind) + ": "}</span>
                                            {b.text}
                                        </li>
                                    }}
                                </ul>
                            </CardContent>
                        }}
                    </Card>
                }}
            </div>
        }}
    </div>
}
