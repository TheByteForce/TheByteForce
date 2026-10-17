"""Citizen: track a request by its reference number."""

import from "@jac/runtime" { useLocation }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, CheckmarkCircle01Icon }
import type from ekata.portal { CitizenStatus }
import from ekata.portal_api { track_request }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.app.desk_state { use_desk, saved_refs, remember_ref }
import from ...components.app.page_parts { PageHero, EmptyNote }
import from ...lib.utils { cn }

glob STAGES: list[str] = [
    "Received", "Sent to your division", "Officer confirmed", "A group accepted", "Help is on the way", "Help delivered or safe"
];

def:pub Stepper(stage: int) -> JsxElement {
    <ol className="grid grid-cols-1 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        {for (i, s) in enumerate(STAGES) {
            <li
                key={s}
                className={cn(
                    "flex items-center gap-2 rounded-full border pt-2 pb-2 pl-3 pr-3 text-sm",
                    "border-emerald-200 bg-emerald-50 font-medium text-emerald-800" if i <= stage else "text-muted-foreground"
                )}
                aria-current={"step" if i == stage else None}
            >
                <span className={cn(
                    "flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
                    "bg-emerald-600 text-white" if i <= stage else "bg-muted text-muted-foreground"
                )}>
                    {str(i + 1)}
                </span>
                {s}
            </li>
        }}
    </ol>
}

def:pub TrackPage -> JsxPage {
    ctx: any = use_desk();
    location = useLocation();
    search: str = location.search or "";
    preset: str = search.split("ref=")[1].split("&")[0] if "ref=" in search else "";
    has draft: str = "";
    has active: str = "";
    has refs: list[str] = [];
    has status: CitizenStatus | None = None;
    has loading: bool = False;

    async can with entry {
        refs = saved_refs();
        if preset != "" {
            draft = preset;
            active = preset;
        }
    }

    async can with (ctx.tick, active) entry {
        if active == "" {
            return;
        }
        loading = status is None;
        try {
            status = await track_request(active, ctx.tick);
        } except Exception as ex {
            status = None;
        }
        loading = False;
    }

    def check(ref: str) -> None {
        r = ref.strip().upper();
        if r == "" {
            return;
        }
        draft = r;
        status = None;
        active = r;
        refs = remember_ref(r);
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Citizen · Track my request"
            title="See where your request is."
            description="Enter the reference number you received when you sent your message. This page updates by itself."
            image="/static/assets/images/boat-crossing.jpg"
            imageAlt="Rescue workers crossing flood water by boat"
            capsules={[["Received", "blue"], ["Officer confirmed", "violet"], ["Help reached you", "green"]]}
        />

        <Card>
            <CardHeader>
                <CardTitle>Reference number</CardTitle>
                <CardDescription>It looks like m012 or W-003.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
                <form className="flex flex-wrap gap-2" onSubmit={lambda (e: FormEvent) { e.preventDefault(); check(draft); }}>
                    <label htmlFor="ref" className="sr-only">Reference number</label>
                    <Input
                        id="ref"
                        value={draft}
                        className="h-10 max-w-xs text-base"
                        placeholder="Reference number"
                        onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}
                    />
                    <Button type="submit" size="lg" className="rounded-full pl-4 pr-4" disabled={draft.strip() == ""}>
                        <HugeiconsIcon icon={Search01Icon} strokeWidth={2} data-icon="inline-start" />
                        Check
                    </Button>
                </form>
                {if len(refs) > 0 {
                    <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm text-muted-foreground">Your recent numbers</span>
                        {for r in refs {
                            <button
                                key={r}
                                type="button"
                                className={cn("rounded-full border pt-1 pb-1 pl-3 pr-3 font-mono text-sm transition-colors hover:bg-muted", "border-primary bg-blue-50" if r == active else "")}
                                onClick={lambda (e: MouseEvent) { check(r); }}
                            >
                                {r}
                            </button>
                        }}
                    </div>
                }}
            </CardContent>
        </Card>

        {if active != "" and not loading and (status is None or not status.found) {
            <EmptyNote
                title="We cannot find that number"
                description="Check the number and try again. A message sent in the last few seconds may take a moment to appear."
                icon={Search01Icon}
            />
        } elif status is not None and status.found {
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} className="size-5 text-emerald-600" />
                        {status.stage_label}
                    </CardTitle>
                    <CardDescription>{status.detail}</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <Stepper stage={status.stage} />
                    <div className="grid gap-2 text-sm sm:grid-cols-3">
                        {if status.ds != "" {
                            <p><span className="text-muted-foreground">Division </span>{status.ds}</p>
                        }}
                        {if status.officer != "" {
                            <p><span className="text-muted-foreground">Officer </span>{status.officer}</p>
                        }}
                        {if status.inc_id != "" {
                            <p><span className="text-muted-foreground">Case </span><span className="font-mono">{status.inc_id}</span></p>
                        }}
                    </div>
                    {if len(status.help) > 0 {
                        <div>
                            <p className="text-sm font-medium">Help arranged</p>
                            <ul className="mt-2 list-disc pl-5 text-sm text-muted-foreground">
                                {for h in status.help {
                                    <li key={h}>{h}</li>
                                }}
                            </ul>
                        </div>
                    }}
                </CardContent>
            </Card>
        }}
    </div>
}
