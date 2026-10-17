"""Analyst review and rumour comparison; no warnings are automatically published."""
import from "react" { useEffect }
import type from ekata.casework { AppealView, RumourView }
import from ekata.case_api { appeals, rumour_log, decide_appeal, investigate_appeal }
import from ...components.ui.button { Button }

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
            error = str(e);
        }
    }
    async def decide(id: str, approve: bool) -> None {
        busy = True;
        try {
            await decide_appeal(id, analyst, approve);
            await refresh();
            error = "";
        } except Exception as e {
            error = str(e);
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
            error = str(e);
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
    <main className="mx-auto max-w-7xl p-5">
        <header className="mb-5 flex flex-wrap items-center gap-4">
            <div>
                <h1 className="text-2xl font-bold">Appeals & rumours</h1>
                <p className="text-muted-foreground">
                    Synthetic data · analyst review · no automatic public warnings
                </p>
            </div>
            <label className="ml-auto">
                Acting as{" "}
                <select
                    className="rounded border p-2"
                    value={analyst}
                    onChange={lambda (e: ChangeEvent) { analyst = e.target.value; }}
                >
                    <option>Analyst A</option>
                    <option>Analyst B</option>
                </select>
            </label>
            <Button variant="outline" onClick={lambda (e: MouseEvent) { refresh(); }}>
                Refresh
            </Button>
        </header>
        {if error != "" {
            <p role="alert" className="mb-4 rounded border border-red-600 p-3">
                {error}
            </p>
        }}
        <div className="grid gap-5 lg:grid-cols-2">
            <section aria-label="Appeal review">
                <h2 className="mb-3 text-xl font-semibold">Donation appeals</h2>
                {if len(items) == 0 {
                    <p className="rounded border border-dashed p-6">
                        Replay or paste an appeal to begin. Unverified never means scam.
                    </p>
                }}
                {for ap in items {
                    <article
                        key={ap.appeal_id}
                        className="mb-4 min-w-0 break-words rounded-xl border bg-card p-4 shadow-sm"
                    >
                        <div className="flex flex-wrap justify-between gap-2">
                            <span className="font-mono text-sm">
                                {ap.appeal_id + " · " + ap.storm_time}
                            </span>
                            <strong className="rounded border px-2 py-1 text-sm">
                                {ap.verdict}
                            </strong>
                        </div>
                        <p className="my-3 whitespace-pre-wrap break-words">
                            {ap.text}
                        </p>
                        <p className="rounded bg-muted p-3 text-sm">
                            <strong>Why: </strong>
                            {ap.reason}
                        </p>
                        <ul className="my-3 space-y-2 text-sm">
                            {for ev in ap.evidence {
                                <li key={ev.ref + ev.kind} className="border-l-2 pl-3">
                                    <strong>{ev.ref}</strong>
                                    {": " + ev.text}
                                </li>
                            }}
                        </ul>
                        <p className="text-sm text-muted-foreground">
                            {("Analyst approved by " + ap.approved_by)
                                if ap.approved_by != ""
                                else "Pending analyst approval · review finding only"}
                        </p>
                        <div className="mt-3 flex flex-wrap gap-2">
                            <Button
                                disabled={busy}
                                onClick={lambda (e: MouseEvent) { investigate(
                                    ap.appeal_id
                                ); }}
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
                                {"Approve reviewed verdict"
                                    if ap.approved_by == ""
                                    else "Withdraw approval"}
                            </Button>
                        </div>
                    </article>
                }}
            </section>
            <section aria-label="Rumour log">
                <h2 className="mb-3 text-xl font-semibold">Rumour log</h2>
                <p className="mb-3 text-sm text-muted-foreground">
                    These messages stay out of the rescue queue. Bulletins are fictional demo notices.
                </p>
                {if len(rumours) == 0 {
                    <p className="rounded border border-dashed p-6">
                        No rumour messages yet.
                    </p>
                }}
                {for rumour in rumours {
                    <article
                        key={rumour.source_id}
                        className="mb-4 min-w-0 break-words rounded-xl border bg-card p-4 shadow-sm"
                    >
                        <p className="font-mono text-sm">
                            {rumour.source_id + " · " + rumour.storm_time}
                        </p>
                        <p className="my-3">{rumour.claim}</p>
                        <strong className="text-sm">{rumour.stance}</strong>
                        {for b in rumour.bulletins {
                            <blockquote
                                key={b.ref}
                                className="mt-3 border-l-4 border-primary bg-muted p-3 text-sm"
                            >
                                <strong>{b.ref}</strong>
                                <p>{b.text}</p>
                            </blockquote>
                        }}
                        {if len(rumour.bulletins) == 0 {
                            <p className="mt-2 text-sm text-muted-foreground">
                                No matching bulletin. The claim remains unconfirmed.
                            </p>
                        }}
                    </article>
                }}
            </section>
        </div>
    </main>
}
