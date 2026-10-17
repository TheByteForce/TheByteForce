"""Overview: the shift at a glance, with links into each detailed page."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    InboxIcon, GitMergeIcon, CallIcon, Alert02Icon, ArrowRight01Icon, Activity01Icon, PlayIcon
}
import type from ekata.views { QueueRow, Metrics, TraceRow }
import type from ekata.alert_level { AlertRow }
import from ekata.api { call_queue, metrics }
import from ekata.coordination_api { alert_levels }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.button { Button }
import from ..components.app.desk_state { use_desk }
import from ..components.app.items { QueueItem, TraceItem, fetch_trace }
import from ..components.app.tags { LevelTag }
import from ..components.app.page_parts { EmptyNote, LoadingRows }

def:pub StatCard(label: str, value: str, note: str, icon: any) -> JsxElement {
    <Card>
        <CardHeader>
            <div className="flex items-center justify-between">
                <CardDescription>{label}</CardDescription>
                <HugeiconsIcon icon={icon} strokeWidth={2} className="size-4 text-muted-foreground" />
            </div>
            <CardTitle className="text-3xl font-semibold tabular-nums">{value}</CardTitle>
        </CardHeader>
        <CardContent>
            <p className="text-sm text-muted-foreground">{note}</p>
        </CardContent>
    </Card>
}

def:pub Overview -> JsxPage {
    ctx: any = use_desk();
    has stats: Metrics | None = None;
    has queue: list[QueueRow] = [];
    has alerts: list[AlertRow] = [];
    has recent: list[TraceRow] = [];
    has loaded: bool = False;

    async def load_all(t: int) -> None {
        try {
            stats = await metrics(t);
            queue = await call_queue(t);
            alerts = await alert_levels(t);
            rows = await fetch_trace(0, t);
            recent = rows;
            loaded = True;
        } except Exception as ex {
            loaded = True;
        }
    }

    async can with [ctx.tick] entry {
        await load_all(ctx.tick);
    }

    seeded: bool = bool(ctx.demo and ctx.demo.seeded and ctx.demo.position > 0);
    urgent: list[AlertRow] = [a for a in alerts if a.level >= 5];
    newest: list[TraceRow] = list(reversed(recent))[:5];

    <div className="flex flex-col gap-6">
        <section className="relative overflow-hidden rounded-xl border">
            <img
                src="/static/assets/images/rescue-team.jpg"
                alt="A water rescue team in an inflatable boat moving through a flooded street"
                className="absolute inset-0 h-full w-full object-cover"
            />
            <div className="absolute inset-0 bg-gradient-to-r from-black/85 via-black/65 to-black/20"></div>
            <div className="relative flex max-w-2xl flex-col gap-4 pt-12 pb-12 pl-6 pr-6 text-white sm:pt-16 sm:pb-16 sm:pl-10 sm:pr-10">
                <p className="text-sm font-medium text-white/80">CrisisConnect · Flood response desk</p>
                <h1 className="text-balance text-3xl font-bold tracking-tight sm:text-4xl">
                    Every SOS in one trusted queue.
                </h1>
                <p className="text-balance text-base leading-relaxed text-white/85">
                    Messages from SMS, WhatsApp, the hotline and the web are merged into incidents, ranked by who needs a call first, and every decision is logged.
                </p>
                <div className="flex flex-wrap gap-2">
                    <Button asChild={True}>
                        <Link to="/queue">
                            Open the call queue
                            <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} data-icon="inline-end" />
                        </Link>
                    </Button>
                    {if not seeded {
                        <Button variant="secondary" onClick={lambda (e: MouseEvent) { ctx.toggle(); }}>
                            <HugeiconsIcon icon={PlayIcon} strokeWidth={2} data-icon="inline-start" />
                            Start the demo night
                        </Button>
                    }}
                </div>
            </div>
        </section>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
                label="Messages in"
                value={str(stats.messages) if stats else "—"}
                note={f"{stats.rescue_messages} asking for rescue" if stats else "Loading"}
                icon={InboxIcon}
            />
            <StatCard
                label="Open incidents"
                value={str(stats.incidents) if stats else "—"}
                note={f"{stats.calls_needed} calls needed" if stats else "Loading"}
                icon={GitMergeIcon}
            />
            <StatCard
                label="Calls saved by merging"
                value={str(stats.calls_saved) if stats else "—"}
                note="Duplicate reports folded into one incident"
                icon={CallIcon}
            />
            <StatCard
                label="Life at risk"
                value={str(len(urgent)) if stats else "—"}
                note="Level 5 alerts: call immediately"
                icon={Alert02Icon}
            />
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
            <Card className="lg:col-span-3">
                <CardHeader>
                    <div className="flex items-start justify-between gap-4">
                        <div className="flex flex-col gap-1">
                            <CardTitle>Call next</CardTitle>
                            <CardDescription>The five most urgent open incidents.</CardDescription>
                        </div>
                        <Button variant="ghost" size="sm" asChild={True}>
                            <Link to="/queue">
                                Full queue
                                <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} data-icon="inline-end" />
                            </Link>
                        </Button>
                    </div>
                </CardHeader>
                <CardContent>
                    {if not loaded {
                        <LoadingRows count={3} className="h-20" />
                    } elif len(queue) == 0 {
                        <EmptyNote
                            title="No incidents yet"
                            description="Start the demo night or paste a message in the inbox. Incidents appear here ranked by urgency."
                            icon={CallIcon}
                        />
                    } else {
                        <ol className="flex flex-col gap-2">
                            {for r in queue[:5] {
                                <QueueItem key={r.inc_id} row={r} compact={True} />
                            }}
                        </ol>
                    }}
                </CardContent>
            </Card>

            <div className="flex flex-col gap-6 lg:col-span-2">
                <Card>
                    <CardHeader>
                    <div className="flex items-start justify-between gap-4">
                        <div className="flex flex-col gap-1">
                            <CardTitle>Life at risk now</CardTitle>
                            <CardDescription>Level 5 alerts from the alert board.</CardDescription>
                        </div>
                        <Button variant="ghost" size="sm" asChild={True}>
                                <Link to="/alerts">All levels</Link>
                            </Button>
                    </div>
                </CardHeader>
                    <CardContent>
                        {if len(urgent) == 0 {
                            <p className="text-sm text-muted-foreground">No Level 5 alerts right now.</p>
                        }}
                        <ul className="flex flex-col divide-y">
                            {for a in urgent[:5] {
                                <li key={a.inc_id} className="flex items-center gap-3 pt-3 pb-3 first:pt-0">
                                    <LevelTag level={a.level} />
                                    <span className="min-w-0 flex-1 truncate text-sm">{a.reason}</span>
                                    <Link to={"/incidents/" + a.inc_id} className="font-mono text-xs text-primary underline-offset-4 hover:underline">
                                        {a.inc_id}
                                    </Link>
                                </li>
                            }}
                        </ul>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                    <div className="flex items-start justify-between gap-4">
                        <div className="flex flex-col gap-1">
                            <CardTitle>Latest decisions</CardTitle>
                            <CardDescription>What the agents did, and what the referee allowed.</CardDescription>
                        </div>
                        <Button variant="ghost" size="sm" asChild={True}>
                                <Link to="/activity">
                                    <HugeiconsIcon icon={Activity01Icon} strokeWidth={2} data-icon="inline-start" />
                                    All
                                </Link>
                            </Button>
                    </div>
                </CardHeader>
                    <CardContent>
                        {if len(newest) == 0 {
                            <p className="text-sm text-muted-foreground">No decisions yet.</p>
                        }}
                        <ol>
                            {for r in newest {
                                <TraceItem key={str(r.seq)} r={r} />
                            }}
                        </ol>
                    </CardContent>
                </Card>
            </div>
        </div>
    </div>
}
