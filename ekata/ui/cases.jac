"""Appeals and rumours review. No warning is published automatically."""
import from "react" { useEffect }
import type from ekata.casework { AppealView, RumourView }
import from ekata.case_api { appeals, rumour_log, decide_appeal, investigate_appeal }
import from ...components.ui.button { Button }
import from .atoms { Empty, VerdictBadge }

def:pub Cases -> JsxElement {
    has items: list[AppealView] = [];
    has rumours: list[RumourView] = [];
    has tick: int = 0;
    has busy: bool = False;
    has error: str = "";
    has analyst: str = "Analyst A";
    async def refresh -> None {
        try {
            tick = tick + 1;
            items = await appeals(tick);
            rumours = await rumour_log(tick);
        } except Exception as e {
            error = "Could not load cases: " + str(e);
        }
    }
    async def decide(id: str, approve: bool) -> None {
        busy = True;
        try {
            await decide_appeal(id, analyst, approve);
            await refresh();
            error = "";
        } except Exception as e {
            error = "Could not save the decision: " + str(e);
        }
        busy = False;
    }
    async def investigate(id: str) -> None {
        busy = True;
        try {
            await investigate_appeal(id);
            await refresh();
            error = "";
        } except Exception as e {
            error = "The investigation failed: " + str(e);
        }
        busy = False;
    }
    async can with entry {
        await refresh();
    }
    useEffect(
        lambda {
            timer = setInterval(lambda { refresh(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        []
    );
    <section aria-label="Appeals and rumours">
        <div className="mb-4 flex flex-wrap items-center gap-3">
            <p className="text-[15px] text-muted-foreground">
                An analyst reviews each finding. Nothing is published to the public automatically.
            </p>
            <label className="ml-auto flex items-center gap-2 text-[13px]">
                {"Reviewing as"}
                <select
                    className="rounded-md border border-input bg-card px-2 py-1.5 text-[15px] focus-visible:outline-2 focus-visible:outline-primary"
                    value={analyst}
                    onChange={lambda (e: ChangeEvent) { analyst = e.target.value; }}
                >
                    <option>Analyst A</option>
                    <option>Analyst B</option>
                </select>
            </label>
        </div>
        {if error != "" {
            <p
                role="alert"
                className="mb-4 rounded-md border border-blocked/30 bg-blocked-soft p-3 text-[15px] text-blocked"
            >
                {error}
            </p>
        }}
        <div className="grid gap-8 lg:grid-cols-2">
            <div aria-label="Appeal review">
                <h2 className="mb-2 text-[17px] font-semibold">Donation appeals</h2>
                {if len(items) == 0 {
                    <Empty
                        title="No appeals yet"
                        hint="Appeals appear here when someone sends one. Not verified does not mean a scam."
                    />
                }}
                <ul className="divide-y divide-border border-y border-border">
                    {for ap in items {
                        <li key={ap.appeal_id} className="min-w-0 break-words py-4">
                            <div className="flex flex-wrap items-center gap-2">
                                <VerdictBadge verdict={ap.verdict}/>
                                <span className="text-[13px] text-muted-foreground">
                                    {"Received " + ap.storm_time}
                                </span>
                            </div>
                            <p className="mt-2 whitespace-pre-wrap break-words text-[15px]">
                                {ap.text}
                            </p>
                            <p className="mt-2 text-[15px]">
                                <span className="font-semibold">{"Why: "}</span>
                                {ap.reason}
                            </p>
                            {if len(ap.evidence) > 0 {
                                <ul
                                    className="mt-2 space-y-1.5 border-l-2 border-border pl-3 text-[13px] text-muted-foreground"
                                >
                                    {for ev in ap.evidence {
                                        <li key={ev.ref + ev.kind}>
                                            <span className="font-semibold text-foreground">
                                                {ev.ref}
                                            </span>
                                            {": " + ev.text}
                                        </li>
                                    }}
                                </ul>
                            }}
                            {if ap.case_summary != "" {
                                <p className="mt-2 text-[13px] text-muted-foreground">
                                    {ap.case_summary}
                                </p>
                            }}
                            {if ap.warning_draft != "" {
                                <div className="mt-3 rounded-md border border-border bg-muted p-3">
                                    <p className="text-[13px] font-semibold">
                                        Warning draft, not published
                                    </p>
                                    <p className="mt-1 whitespace-pre-wrap text-[15px]">
                                        {ap.warning_draft}
                                    </p>
                                </div>
                            }}
                            <p className="mt-2 text-[13px] text-muted-foreground">
                                {("Approved by " + ap.approved_by)
                                    if ap.approved_by != ""
                                    else "Waiting for analyst approval. This is a review finding only."}
                            </p>
                            <div className="mt-3 flex flex-wrap gap-2">
                                <Button
                                    disabled={busy}
                                    onClick={lambda (e: MouseEvent) { investigate(ap.appeal_id); }}
                                >
                                    Investigate with AI
                                </Button>
                                <Button
                                    variant="outline"
                                    disabled={busy}
                                    onClick={lambda (e: MouseEvent) { decide(
                                        ap.appeal_id, ap.approved_by == ""
                                    ); }}
                                >
                                    {"Approve verdict" if ap.approved_by == "" else "Withdraw approval"}
                                </Button>
                            </div>
                        </li>
                    }}
                </ul>
            </div>
            <div aria-label="Rumour log">
                <h2 className="mb-1 text-[17px] font-semibold">Rumour log</h2>
                <p className="mb-2 text-[13px] text-muted-foreground">
                    These messages stay out of the rescue queue.
                </p>
                {if len(rumours) == 0 {
                    <Empty title="No rumours yet"/>
                }}
                <ul className="divide-y divide-border border-y border-border">
                    {for rumour in rumours {
                        <li key={rumour.source_id} className="min-w-0 break-words py-4">
                            <p className="text-[13px] text-muted-foreground">
                                {"Received " + rumour.storm_time}
                            </p>
                            <p className="mt-1 text-[15px]">{rumour.claim}</p>
                            <p className="mt-1 text-[13px] font-semibold">
                                {"Official position: " + (
                                    "contradicted" if rumour.stance == "CONTRADICTED"
                                    else ("confirmed" if rumour.stance == "CONFIRMED" else "not confirmed")
                                )}
                            </p>
                            {for b in rumour.bulletins {
                                <blockquote
                                    key={b.ref}
                                    className="mt-2 border-l-2 border-primary pl-3 text-[13px]"
                                >
                                    <span className="font-semibold">{b.ref}</span>
                                    <p className="text-muted-foreground">{b.text}</p>
                                </blockquote>
                            }}
                            {if len(rumour.bulletins) == 0 {
                                <p className="mt-1 text-[13px] text-muted-foreground">
                                    No matching bulletin. The claim stays unconfirmed.
                                </p>
                            }}
                        </li>
                    }}
                </ul>
            </div>
        </div>
    </section>
}
