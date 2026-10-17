"""Incident detail: evidence, merge decisions, the call log and agent decisions."""

import from "@jac/runtime" { Link, useParams }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    ArrowLeft01Icon, Search01Icon, CheckmarkCircle01Icon, Cancel01Icon
}
import type from ekata.views { IncidentView }
import from ekata.api { incident_detail, decide_merge, log_call }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.native_select { NativeSelectOption }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.ui.breadcrumb {
    Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbLink, BreadcrumbPage, BreadcrumbSeparator
}
import from ...components.app.desk_state { use_desk }
import from ...components.app.items { MessageItem, TraceItem }
import from ...components.app.tags { Tag, VulnerableTag, RefereeTag, status_tone }
import from ...components.app.labels { people_label, place_label, call_outcome_label, pretty, plural }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, SelectField }

def:pub incident_capsules(inc: IncidentView) -> list[list[str]] {
    out: list[list[str]] = [
        [pretty(inc.status), status_tone(inc.status)],
        [f"Priority {inc.priority:.1f}", "blue"]
    ];
    if inc.claimed_by != "" {
        out = out + [["Claimed by " + inc.claimed_by, "violet"]];
    }
    for v in inc.vulnerable {
        out = out + [["Vulnerable: " + v, "amber"]];
    }
    out = out + [[plural(len(inc.calls), "call logged", "calls logged"), "green"]];
    return out;
}

def:pub IncidentPage -> JsxPage {
    ctx: any = use_desk();
    params = useParams();
    inc_id: str = params["id"] or "";
    has inc: IncidentView | None = None;
    has loaded: bool = False;
    has outcome: str = "";
    has note: str = "";
    has saving: bool = False;
    has notice: str = "";
    has err: str = "";

    async def load(t: int) -> None {
        if inc_id == "" {
            loaded = True;
            return;
        }
        try {
            inc = await incident_detail(inc_id, t);
        } except Exception as ex {
            err = "Could not load the incident: " + str(ex);
        }
        loaded = True;
    }

    async def decide(msgId: str, approve: bool) -> None {
        if saving {
            return;
        }
        saving = True;
        err = "";
        notice = "";
        try {
            iv = await decide_merge(msgId, inc_id, approve, ctx.desk);
            if iv is not None {
                inc = iv;
            }
            notice = ("Approved" if approve else "Rejected") + f" the merge of {msgId} as {ctx.desk}.";
            ctx.bump();
        } except Exception as ex {
            err = "Could not record the decision: " + str(ex);
        }
        saving = False;
    }

    async def submit_call -> None {
        if saving or outcome == "" {
            return;
        }
        saving = True;
        err = "";
        notice = "";
        try {
            iv = await log_call(inc_id, outcome, ctx.desk, note.strip());
            if iv is not None {
                inc = iv;
            }
            notice = f"Call logged: {call_outcome_label(outcome)} ({ctx.desk}).";
            outcome = "";
            note = "";
            ctx.bump();
        } except Exception as ex {
            err = "Could not log the call: " + str(ex);
        }
        saving = False;
    }

    async can with (ctx.tick, inc_id) entry {
        await load(ctx.tick);
    }

    <div className="flex flex-col gap-6">
        <Breadcrumb>
            <BreadcrumbList>
                <BreadcrumbItem>
                    <BreadcrumbLink asChild={True}>
                        <Link to="/queue">Call queue</Link>
                    </BreadcrumbLink>
                </BreadcrumbItem>
                <BreadcrumbSeparator />
                <BreadcrumbItem>
                    <BreadcrumbPage>{inc_id}</BreadcrumbPage>
                </BreadcrumbItem>
            </BreadcrumbList>
        </Breadcrumb>

        {if not loaded {
            <LoadingRows count={3} className="h-32" />
        } elif inc is None {
            <EmptyNote
                title="Incident not found"
                description={f"{inc_id} is not an open incident. It may have been merged into another one, or the demo data was reloaded."}
                icon={Search01Icon}
            >
                <Button variant="outline" asChild={True}>
                    <Link to="/queue">
                        <HugeiconsIcon icon={ArrowLeft01Icon} strokeWidth={2} data-icon="inline-start" />
                        Back to the call queue
                    </Link>
                </Button>
            </EmptyNote>
        } else {
            <div className="flex flex-col gap-6">
                <PageHero
                    eyebrow={"Incident " + inc.inc_id}
                    title={people_label(inc.headcount) + " · " + place_label(inc.place)}
                    image="/static/assets/images/aerial-rescue.jpg"
                    imageAlt="A rescue helicopter above a flooded river valley"
                    capsules={incident_capsules(inc)}
                />

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

                <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
                    <div className="flex flex-col gap-6 lg:col-span-2">
                        <Card>
                            <CardHeader>
                                <CardTitle>Summary</CardTitle>
                                <CardDescription>What the messages say, merged into one picture.</CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-4">
                                {if inc.summary != "" {
                                    <p className="leading-relaxed">{inc.summary}</p>
                                }}
                                <div className="flex flex-wrap gap-2">
                                    {for v in inc.vulnerable {
                                        <VulnerableTag key={v} flag={v} />
                                    }}
                                    {for n in inc.needs {
                                        <Tag key={n} label={"Needs " + n} tone="blue" />
                                    }}
                                    {if len(inc.vulnerable) == 0 and len(inc.needs) == 0 {
                                        <span className="text-sm text-muted-foreground">No vulnerable groups or needs recorded.</span>
                                    }}
                                </div>
                            </CardContent>
                        </Card>

                        <Card>
                            <CardHeader>
                                <CardTitle>{f"Messages ({len(inc.messages)})"}</CardTitle>
                                <CardDescription>Every report cited as evidence for this incident.</CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-2">
                                {if len(inc.messages) == 0 {
                                    <p className="text-sm text-muted-foreground">No messages are attached yet.</p>
                                }}
                                {for m in inc.messages {
                                    <MessageItem key={m.msg_id} m={m} />
                                }}
                            </CardContent>
                        </Card>

                        <Card>
                            <CardHeader>
                                <CardTitle>{f"Merge proposals ({len(inc.proposals)})"}</CardTitle>
                                <CardDescription>Messages that may describe this same incident. Unclear cases need a person.</CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-2">
                                {if len(inc.proposals) == 0 {
                                    <p className="text-sm text-muted-foreground">No merge proposals for this incident.</p>
                                }}
                                {for p in inc.proposals {
                                    <div key={p.msg_id + ">" + p.inc_id} className="rounded-lg border pt-4 pb-4 pl-4 pr-4">
                                        <div className="flex flex-wrap items-center gap-2">
                                            <span className="font-mono text-sm">{p.msg_id + " → " + p.inc_id}</span>
                                            <span className="text-sm text-muted-foreground tabular-nums">{f"score {p.score:.2f}"}</span>
                                            <span className="ml-auto"><RefereeTag outcome={p.outcome} /></span>
                                        </div>
                                        {if p.reason != "" {
                                            <p className="mt-2 text-sm text-muted-foreground">{p.reason}</p>
                                        }}
                                        {if p.outcome == "NEEDS_HUMAN" {
                                            <div className="mt-4 flex flex-wrap gap-2">
                                                <Button size="sm" className="rounded-full pl-3 pr-3" disabled={saving} onClick={lambda (e: MouseEvent) { decide(p.msg_id, True); }}>
                                                    <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} data-icon="inline-start" />
                                                    Approve merge
                                                </Button>
                                                <Button size="sm" variant="outline" className="rounded-full pl-3 pr-3" disabled={saving} onClick={lambda (e: MouseEvent) { decide(p.msg_id, False); }}>
                                                    <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} data-icon="inline-start" />
                                                    Reject
                                                </Button>
                                            </div>
                                        }}
                                    </div>
                                }}
                            </CardContent>
                        </Card>

                        <Card>
                            <CardHeader>
                                <CardTitle>{f"Similar incidents ({len(inc.candidates)})"}</CardTitle>
                                <CardDescription>Other incidents that share a phone, name or place.</CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-2">
                                {if len(inc.candidates) == 0 {
                                    <p className="text-sm text-muted-foreground">No other incident shares details with this one.</p>
                                }}
                                {for c in inc.candidates {
                                    <div key={c.inc_id} className="rounded-lg border pt-4 pb-4 pl-4 pr-4">
                                        <Link to={"/incidents/" + c.inc_id} className="font-mono text-sm font-medium text-primary underline-offset-4 hover:underline">
                                            {c.inc_id}
                                        </Link>
                                        <ul className="mt-2 list-disc pl-5 text-sm text-muted-foreground">
                                            {for rs in c.reasons {
                                                <li key={rs}>{rs}</li>
                                            }}
                                        </ul>
                                    </div>
                                }}
                            </CardContent>
                        </Card>
                    </div>

                    <div className="flex flex-col gap-6">
                        <Card>
                            <CardHeader>
                                <CardTitle>Log a call</CardTitle>
                                <CardDescription>{"Recorded as " + ctx.desk + ". Change the desk in the sidebar."}</CardDescription>
                            </CardHeader>
                            <CardContent>
                                <form
                                    className="flex flex-col gap-4"
                                    onSubmit={lambda (e: FormEvent) { e.preventDefault(); submit_call(); }}
                                >
                                    <div className="flex flex-col gap-2">
                                        <label htmlFor="call-outcome" className="text-sm font-medium">Outcome</label>
                                        <SelectField
                                            id="call-outcome"
                                            value={outcome}
                                            className="w-full"
                                            onChange={lambda (e: ChangeEvent) { outcome = e.target.value; }}
                                        >
                                            <NativeSelectOption value="">Choose an outcome</NativeSelectOption>
                                            <NativeSelectOption value="REACHED_CONFIRMED">Reached, confirmed</NativeSelectOption>
                                            <NativeSelectOption value="NO_ANSWER">No answer</NativeSelectOption>
                                            <NativeSelectOption value="RESCUED">Rescued</NativeSelectOption>
                                            <NativeSelectOption value="STILL_IN_NEED">Still in need</NativeSelectOption>
                                        </SelectField>
                                    </div>
                                    <div className="flex flex-col gap-2">
                                        <label htmlFor="call-note" className="text-sm font-medium">Note (optional)</label>
                                        <Input
                                            id="call-note"
                                            value={note}
                                            onChange={lambda (e: ChangeEvent) { note = e.target.value; }}
                                        />
                                    </div>
                                    <Button type="submit" className="rounded-full" disabled={saving or outcome == ""}>
                                        {"Saving..." if saving else "Log call"}
                                    </Button>
                                </form>
                            </CardContent>
                        </Card>

                        <Card>
                            <CardHeader>
                                <CardTitle>{f"Call history ({len(inc.calls)})"}</CardTitle>
                            </CardHeader>
                            <CardContent>
                                {if len(inc.calls) == 0 {
                                    <p className="text-sm text-muted-foreground">No calls logged yet.</p>
                                }}
                                <ol className="flex flex-col divide-y">
                                    {for (i, c) in enumerate(inc.calls) {
                                        <li key={str(i)} className="pt-3 pb-3 text-sm first:pt-0">
                                            <div className="flex flex-wrap items-center gap-2">
                                                <span className="font-medium">{call_outcome_label(c.outcome)}</span>
                                                <span className="text-muted-foreground">{c.desk}</span>
                                                <span className="ml-auto font-mono text-xs text-muted-foreground">{c.storm_time}</span>
                                            </div>
                                            {if c.note != "" {
                                                <p className="mt-1 text-muted-foreground">{c.note}</p>
                                            }}
                                        </li>
                                    }}
                                </ol>
                            </CardContent>
                        </Card>

                        <Card>
                            <CardHeader>
                                <CardTitle>Agent decisions</CardTitle>
                                <CardDescription>Each step taken on this incident and the referee outcome.</CardDescription>
                            </CardHeader>
                            <CardContent>
                                {if len(inc.trace) == 0 {
                                    <p className="text-sm text-muted-foreground">No decisions recorded.</p>
                                }}
                                <ol>
                                    {for r in inc.trace {
                                        <TraceItem key={str(r.seq)} r={r} stacked={True} />
                                    }}
                                </ol>
                            </CardContent>
                        </Card>
                    </div>
                </div>
            </div>
        }}
    </div>
}
