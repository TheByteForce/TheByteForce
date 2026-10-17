"""Officer: the division's call queue, most vulnerable first."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Call02Icon, ArrowRight01Icon, Location01Icon, UserGroupIcon, Clock01Icon }
import type from ekata.views { QueueRow }
import type from ekata.portal { DivisionView }
import from ekata.portal_api { officer_queue, divisions }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.app.desk_state { use_desk }
import from ...components.app.items { QueueItem }
import from ...components.app.tags { StatusTag, VulnerableTag }
import from ...components.app.labels { plural, people_label, place_label }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }

# When no division is chosen yet: one card per division to pick from.
def:pub DivisionChooser(rows: list[DivisionView], onPick: Callable[[str], None]) -> JsxElement {
    <div className="flex flex-col gap-4">
        <div>
            <h2 className="text-xl font-semibold tracking-tight">Choose your division</h2>
            <p className="text-sm text-muted-foreground">This browser remembers it. You can change it any time in the sidebar.</p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {for d in rows {
                <button
                    key={d.ds}
                    type="button"
                    className="group flex items-center gap-4 rounded-xl border bg-card pt-4 pb-4 pl-4 pr-4 text-left transition-colors hover:bg-muted/50"
                    onClick={lambda (e: MouseEvent) { onPick(d.ds); }}
                >
                    <IconChip icon={Call02Icon} tone={"orange" if d.vulnerable_open > 0 else "blue"} />
                    <span className="min-w-0 flex-1">
                        <span className="block font-medium">{d.ds}</span>
                        <span className="block text-sm text-muted-foreground">{d.district + " district"}</span>
                        <span className="mt-1 block text-sm">{f"{d.open_count} open · {d.unanswered} not yet called"}</span>
                    </span>
                    <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4 text-muted-foreground" />
                </button>
            }}
        </div>
    </div>
}

def:pub NextCall(row: QueueRow) -> JsxElement {
    <Card className="border-orange-200 bg-orange-50/50">
        <CardHeader>
            <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full bg-orange-600 pt-0.5 pb-0.5 pl-3 pr-3 text-xs font-semibold text-white">Next call</span>
                <StatusTag status={row.status} />
                {for v in row.vulnerable {
                    <VulnerableTag key={v} flag={v} />
                }}
            </div>
            <CardTitle className="text-xl leading-snug">{people_label(row.headcount) + " at " + place_label(row.place)}</CardTitle>
            <CardDescription>{row.headline}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
            <div className="flex flex-wrap gap-4 text-sm text-muted-foreground">
                <span className="inline-flex items-center gap-1"><HugeiconsIcon icon={Clock01Icon} strokeWidth={2} className="size-4" />{"Waiting " + row.waiting}</span>
                <span className="inline-flex items-center gap-1"><HugeiconsIcon icon={UserGroupIcon} strokeWidth={2} className="size-4" />{plural(row.msg_count, "message", "messages")}</span>
                <span className="inline-flex items-center gap-1"><HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-4" />{row.inc_id}</span>
            </div>
            {if row.reason != "" {
                <p className="text-sm"><span className="font-medium">Why first: </span>{row.reason}</p>
            }}
            <div>
                <Button asChild={True} className="rounded-full pl-4 pr-4">
                    <Link to={"/officer/cases/" + row.inc_id}>
                        <HugeiconsIcon icon={Call02Icon} strokeWidth={2} data-icon="inline-start" />
                        Open this case
                    </Link>
                </Button>
            </div>
        </CardContent>
    </Card>
}

def:pub OfficerQueuePage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[QueueRow] = [];
    has division_rows: list[DivisionView] = [];
    has loaded: bool = False;

    async can with (ctx.tick, ctx.ds) entry {
        try {
            if ctx.ds == "" {
                division_rows = await divisions(ctx.tick);
                rows = [];
            } else {
                rows = await officer_queue(ctx.ds, ctx.tick);
            }
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    vulnerable_n: int = len([r for r in rows if len(r.vulnerable) > 0]);
    new_n: int = len([r for r in rows if r.status == "NEW"]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Division officer · " + (ctx.ds if ctx.ds != "" else "Call queue")}
            title="Who to call next."
            description="Households in your division, most vulnerable first. Claim a case before you call, confirm it by phone, then ask a relief group for what they need."
            image="/static/assets/images/operations-center.jpg"
            imageAlt="Operators at their desks in an emergency operations centre"
            capsules={[
                [plural(len(rows), "household waiting", "households waiting"), "blue"],
                [f"{vulnerable_n} with vulnerable people", "amber"],
                [f"{new_n} not yet called", "red"]
            ]}
        />
        {if ctx.ds == "" and not loaded {
            <LoadingRows count={3} className="h-20" />
        } elif ctx.ds == "" {
            <DivisionChooser rows={division_rows} onPick={lambda (v: str) { ctx.setDs(v); }} />
        } elif not loaded {
            <LoadingRows count={4} className="h-28" />
        } elif len(rows) == 0 {
            <EmptyNote
                title={"No one is waiting in " + ctx.ds}
                description="New requests for help in your division appear here as soon as they arrive."
                icon={Call02Icon}
            />
        } else {
            <NextCall row={rows[0]} />
            if len(rows) > 1 {
                <div className="flex flex-col gap-2">
                    <h2 className="text-sm font-medium text-muted-foreground">{f"Waiting after that ({len(rows) - 1})"}</h2>
                    <ol className="flex flex-col gap-2">
                        {for r in rows[1:] {
                            <QueueItem key={r.inc_id} row={r} />
                        }}
                    </ol>
                </div>
            }
        }}
    </div>
}
