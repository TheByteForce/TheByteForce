"""Officer: one case. Claim it, call, log the call, fix the facts, and ask a
relief group for what the household needs."""

import from "@jac/runtime" { Link, useParams }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    ArrowLeft01Icon, Search01Icon, CheckmarkCircle01Icon, Cancel01Icon, Call02Icon,
    AiBrain01Icon, TruckIcon, Location01Icon
}
import type from ekata.views { IncidentView }
import type from ekata.portal { DivisionView, RequestView }
import type from ekata.ai.brief { CallBrief }
import from ekata.api { incident_detail, decide_merge, log_call, claim_incident, resolve_change }
import from ekata.case_api { call_brief, refresh_call_brief }
import from ekata.portal_api { divisions, set_gn, resource_kinds, request_resource, incident_requests }
import from ....components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ....components.ui.button { Button }
import from ....components.ui.input { Input }
import from ....components.ui.native_select { NativeSelectOption }
import from ....components.ui.alert { Alert, AlertDescription }
import from ....components.ui.breadcrumb {
    Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbLink, BreadcrumbPage, BreadcrumbSeparator
}
import from ....components.app.desk_state { use_desk }
import from ....components.app.items { MessageItem, TraceItem }
import from ....components.app.tags { Tag, VulnerableTag, RefereeTag, RequestTag, status_tone }
import from ....components.app.labels { people_label, place_label, call_outcome_label, pretty, plural }
import from ....components.app.page_parts { PageHero, EmptyNote, LoadingRows, SelectField, IconChip }
import from ....components.app.portals { officer_desk }

def:pub case_capsules(inc: IncidentView) -> list[list[str]] {
    out: list[list[str]] = [[pretty(inc.status), status_tone(inc.status)], [f"Priority {inc.priority:.1f}", "blue"]];
    if inc.claimed_by != "" {
        out = out + [["Claimed by " + inc.claimed_by, "violet"]];
    }
    for v in inc.vulnerable {
        out = out + [["Vulnerable: " + v, "amber"]];
    }
    out = out + [[plural(len(inc.calls), "call logged", "calls logged"), "green"]];
    return out;
}

def:pub BriefList(title: str, items: list[str], numbered: bool = False) -> JsxElement {
    if len(items) == 0 {
        return <></>;
    }
    <div>
        <p className="text-sm font-medium">{title}</p>
        {if numbered {
            <ol className="mt-2 list-decimal pl-5 text-sm leading-relaxed">
                {for q in items {
                    <li key={q}>{q}</li>
                }}
            </ol>
        } else {
            <ul className="mt-2 list-disc pl-5 text-sm leading-relaxed text-muted-foreground">
                {for q in items {
                    <li key={q}>{q}</li>
                }}
            </ul>
        }}
    </div>
}

def:pub CasePage -> JsxPage {
    ctx: any = use_desk();
    params = useParams();
    inc_id: str = params["id"] or "";
    has inc: IncidentView | None = None;
    has loaded: bool = False;
    has brief: CallBrief | None = None;
    has briefing: bool = False;
    has requests: list[RequestView] = [];
    has kinds: list[str] = [];
    has gns: list[str] = [];
    has gn: str = "";
    has outcome: str = "";
    has note: str = "";
    has saving: bool = False;
    has notice: str = "";
    has err: str = "";

    desk: str = officer_desk(ctx.ds) if ctx.ds != "" else "Divisional desk";
    mine: bool = inc is not None and inc.claimed_by == desk;

    async can with (ctx.tick, inc_id) entry {
        if inc_id == "" {
            loaded = True;
            return;
        }
        try {
            inc = await incident_detail(inc_id, ctx.tick);
            requests = await incident_requests(inc_id, ctx.tick);
        } except Exception as ex {
            err = "Could not load the case: " + str(ex);
        }
        loaded = True;
    }

    async can with (inc_id, ctx.ds) entry {
        try {
            kinds = await resource_kinds();
            brief = await call_brief(inc_id, 0);
            if ctx.ds != "" {
                rows = await divisions(0);
                found: list[str] = [];
                for d in rows {
                    if d.ds == ctx.ds {
                        found = d.gns;
                    }
                }
                gns = found;
            }
        } except Exception as ex {
            kinds = kinds;
        }
    }

    def begin -> bool {
        if saving {
            return False;
        }
        saving = True;
        err = "";
        notice = "";
        return True;
    }

    def done(label: str) -> None {
        notice = label;
        saving = False;
        ctx.bump();
    }

    def failed(ex: any) -> None {
        err = str(ex);
        saving = False;
    }

    async def claim(release: bool) -> None {
        if not begin() {
            return;
        }
        try {
            await claim_incident(inc_id, desk, release);
            done("You released the case." if release else "The case is yours. Call now.");
        } except Exception as ex {
            failed(ex);
        }
    }

    async def submit_call -> None {
        if outcome == "" or not begin() {
            return;
        }
        try {
            await log_call(inc_id, outcome, desk, note.strip());
            done(f"Call logged: {call_outcome_label(outcome)}.");
            outcome = "";
            note = "";
        } except Exception as ex {
            failed(ex);
        }
    }

    async def change(field: str, accept: bool) -> None {
        if not begin() {
            return;
        }
        try {
            await resolve_change(inc_id, field, desk, accept);
            done("Change accepted." if accept else "Kept the old value.");
        } except Exception as ex {
            failed(ex);
        }
    }

    async def merge(msgId: str, approve: bool) -> None {
        if not begin() {
            return;
        }
        try {
            await decide_merge(msgId, inc_id, approve, desk);
            done("Merged into this case." if approve else "Kept as a different case.");
        } except Exception as ex {
            failed(ex);
        }
    }

    async def ask(kind: str) -> None {
        if not begin() {
            return;
        }
        try {
            r = await request_resource(inc_id, kind, desk);
            if r is not None and r.ngo != "" {
                done(f"Asked {r.ngo} for {kind}.");
            } else {
                done(f"No relief group can supply {kind} here right now. The district desk has been told.");
            }
        } except Exception as ex {
            failed(ex);
        }
    }

    async def pin_gn -> None {
        if gn == "" or not begin() {
            return;
        }
        try {
            await set_gn(inc_id, gn, desk);
            done("GN division pinned.");
        } except Exception as ex {
            failed(ex);
        }
    }

    async def prepare_brief -> None {
        if briefing {
            return;
        }
        briefing = True;
        try {
            b = await refresh_call_brief(inc_id);
            if b is not None {
                brief = b;
            }
        } except Exception as ex {
            err = "Could not prepare the questions: " + str(ex);
        }
        briefing = False;
    }

    <div className="flex flex-col gap-6">
        <Breadcrumb>
            <BreadcrumbList>
                <BreadcrumbItem>
                    <BreadcrumbLink asChild={True}>
                        <Link to="/officer">Call queue</Link>
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
                title="Case not found"
                description={f"{inc_id} is not an open case. It may have been merged into another case."}
                icon={Search01Icon}
            >
                <Button variant="outline" className="rounded-full" asChild={True}>
                    <Link to="/officer">
                        <HugeiconsIcon icon={ArrowLeft01Icon} strokeWidth={2} data-icon="inline-start" />
                        Back to the call queue
                    </Link>
                </Button>
            </EmptyNote>
        } else {
            <PageHero
                eyebrow={"Case " + inc.inc_id}
                title={people_label(inc.headcount) + " · " + place_label(inc.place)}
                description={inc.summary}
                image="/static/assets/images/aerial-rescue.jpg"
                imageAlt="A rescue helicopter above a flooded river valley"
                capsules={case_capsules(inc)}
            >
                {if inc.claimed_by == "" {
                    <Button className="rounded-full pl-4 pr-4" disabled={saving} onClick={lambda (e: MouseEvent) { claim(False); }}>
                        <HugeiconsIcon icon={Call02Icon} strokeWidth={2} data-icon="inline-start" />
                        Claim before calling
                    </Button>
                } elif mine {
                    <Button variant="secondary" className="rounded-full pl-4 pr-4" disabled={saving} onClick={lambda (e: MouseEvent) { claim(True); }}>
                        Release this case
                    </Button>
                }}
            </PageHero>

            if notice != "" {
                <Alert>
                    <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} />
                    <AlertDescription>{notice}</AlertDescription>
                </Alert>
            }
            if err != "" {
                <Alert variant="destructive">
                    <AlertDescription>{err}</AlertDescription>
                </Alert>
            }

            if len(inc.pending) > 0 {
                <Card className="border-amber-200 bg-amber-50/50">
                    <CardHeader>
                        <CardTitle>A new message changes the facts</CardTitle>
                        <CardDescription>Accept the change after you confirm it on the call.</CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-2">
                        {for ch in inc.pending {
                            <div key={ch.field + ch.msg_id} className="flex flex-wrap items-center gap-2 rounded-lg border bg-background pt-3 pb-3 pl-3 pr-3 text-sm">
                                <span>{f"{pretty(ch.field)}: {ch.old_value} → {ch.new_value}"}</span>
                                <span className="font-mono text-xs text-muted-foreground">{ch.msg_id}</span>
                                <span className="ml-auto flex gap-2">
                                    <Button size="sm" className="rounded-full pl-3 pr-3" disabled={saving}
                                        onClick={lambda (e: MouseEvent) { change(ch.field, True); }}>
                                        Accept after the call
                                    </Button>
                                    <Button size="sm" variant="outline" className="rounded-full pl-3 pr-3" disabled={saving}
                                        onClick={lambda (e: MouseEvent) { change(ch.field, False); }}>
                                        Keep the old value
                                    </Button>
                                </span>
                            </div>
                        }}
                    </CardContent>
                </Card>
            }

            <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
                <div className="flex flex-col gap-6 lg:col-span-2">
                    <Card>
                        <CardHeader>
                            <div className="flex items-start justify-between gap-4">
                                <div className="flex items-center gap-4">
                                    <IconChip icon={AiBrain01Icon} tone="violet" />
                                    <div className="flex flex-col gap-1">
                                        <CardTitle>What to ask on the call</CardTitle>
                                        <CardDescription>What we know, what is missing, and what to check.</CardDescription>
                                    </div>
                                </div>
                                <Button variant="outline" size="sm" className="rounded-full pl-3 pr-3" disabled={briefing} onClick={lambda (e: MouseEvent) { prepare_brief(); }}>
                                    {"Preparing..." if briefing else "Prepare questions"}
                                </Button>
                            </div>
                        </CardHeader>
                        <CardContent className="flex flex-col gap-4">
                            {if brief is None {
                                <p className="text-sm text-muted-foreground">Prepare questions to get a short call script for this household.</p>
                            } else {
                                <BriefList title="Known" items={brief.known} />
                                <BriefList title="Still missing" items={brief.missing} />
                                <BriefList title="Check this" items={brief.contradictions} />
                                <BriefList title="Questions" items={brief.questions} numbered={True} />
                            }}
                        </CardContent>
                    </Card>

                    <Card>
                        <CardHeader>
                            <CardTitle>{f"What was said ({len(inc.messages)})"}</CardTitle>
                            <CardDescription>Every report attached to this case.</CardDescription>
                        </CardHeader>
                        <CardContent className="flex flex-col gap-2">
                            {for m in inc.messages {
                                <MessageItem key={m.msg_id} m={m} />
                            }}
                        </CardContent>
                    </Card>

                    {if len(inc.proposals) > 0 {
                        <Card>
                            <CardHeader>
                                <CardTitle>{f"Messages that may belong here ({len(inc.proposals)})"}</CardTitle>
                                <CardDescription>When it is not clear, a person decides.</CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-2">
                                {for p in inc.proposals {
                                    <div key={p.msg_id + ">" + p.inc_id} className="rounded-lg border pt-4 pb-4 pl-4 pr-4">
                                        <div className="flex flex-wrap items-center gap-2">
                                            <span className="font-mono text-sm">{p.msg_id + " → " + p.inc_id}</span>
                                            <span className="text-sm tabular-nums text-muted-foreground">{f"score {p.score:.2f}"}</span>
                                            <span className="ml-auto"><RefereeTag outcome={p.outcome} /></span>
                                        </div>
                                        {if p.reason != "" {
                                            <p className="mt-2 text-sm text-muted-foreground">{p.reason}</p>
                                        }}
                                        {if p.outcome == "NEEDS_HUMAN" {
                                            <div className="mt-4 flex flex-wrap gap-2">
                                                <Button size="sm" className="rounded-full pl-3 pr-3" disabled={saving}
                                                    onClick={lambda (e: MouseEvent) { merge(p.msg_id, True); }}>
                                                    <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} data-icon="inline-start" />
                                                    Same case, merge
                                                </Button>
                                                <Button size="sm" variant="outline" className="rounded-full pl-3 pr-3" disabled={saving}
                                                    onClick={lambda (e: MouseEvent) { merge(p.msg_id, False); }}>
                                                    <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} data-icon="inline-start" />
                                                    Different case
                                                </Button>
                                            </div>
                                        }}
                                    </div>
                                }}
                            </CardContent>
                        </Card>
                    }}

                    {if len(inc.candidates) > 0 {
                        <Card>
                            <CardHeader>
                                <CardTitle>{f"Similar cases ({len(inc.candidates)})"}</CardTitle>
                                <CardDescription>Other cases that share a phone, name or place.</CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-2">
                                {for c in inc.candidates {
                                    <div key={c.inc_id} className="rounded-lg border pt-4 pb-4 pl-4 pr-4">
                                        <Link to={"/officer/cases/" + c.inc_id} className="font-mono text-sm font-medium text-primary underline-offset-4 hover:underline">
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
                    }}
                </div>

                <div className="flex flex-col gap-6">
                    <Card>
                        <CardHeader>
                            <CardTitle>Log a call</CardTitle>
                            <CardDescription>{"Recorded as " + desk + "."}</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <form className="flex flex-col gap-4" onSubmit={lambda (e: FormEvent) { e.preventDefault(); submit_call(); }}>
                                <div className="flex flex-col gap-2">
                                    <label htmlFor="call-outcome" className="text-sm font-medium">Outcome</label>
                                    <SelectField id="call-outcome" value={outcome} className="w-full" onChange={lambda (e: ChangeEvent) { outcome = e.target.value; }}>
                                        <NativeSelectOption value="">Choose an outcome</NativeSelectOption>
                                        <NativeSelectOption value="REACHED_CONFIRMED">Reached, confirmed</NativeSelectOption>
                                        <NativeSelectOption value="NO_ANSWER">No answer</NativeSelectOption>
                                        <NativeSelectOption value="RESCUED">Rescued</NativeSelectOption>
                                        <NativeSelectOption value="STILL_IN_NEED">Still in need</NativeSelectOption>
                                    </SelectField>
                                </div>
                                <div className="flex flex-col gap-2">
                                    <label htmlFor="call-note" className="text-sm font-medium">Note (optional)</label>
                                    <Input id="call-note" value={note} onChange={lambda (e: ChangeEvent) { note = e.target.value; }} />
                                </div>
                                <Button type="submit" className="rounded-full" disabled={saving or outcome == ""}>
                                    {"Saving..." if saving else "Log call"}
                                </Button>
                            </form>
                            {if len(inc.calls) > 0 {
                                <ol className="mt-4 flex flex-col divide-y border-t">
                                    {for (i, c) in enumerate(inc.calls) {
                                        <li key={str(i)} className="pt-3 pb-3 text-sm">
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
                            }}
                        </CardContent>
                    </Card>

                    <Card>
                        <CardHeader>
                            <div className="flex items-center gap-4">
                                <IconChip icon={TruckIcon} tone="green" />
                                <div className="flex flex-col gap-1">
                                    <CardTitle>Ask a relief group</CardTitle>
                                    <CardDescription>CrisisConnect sends the request to the group best placed to help.</CardDescription>
                                </div>
                            </div>
                        </CardHeader>
                        <CardContent className="flex flex-col gap-4">
                            <div className="flex flex-wrap gap-2">
                                {for k in kinds {
                                    <Button key={k} size="sm" variant="outline" className="rounded-full pl-3 pr-3" disabled={saving}
                                        onClick={lambda (e: MouseEvent) { ask(k); }}>
                                        {"Ask for " + k}
                                    </Button>
                                }}
                            </div>
                            {if len(requests) > 0 {
                                <ul className="flex flex-col gap-2">
                                    {for r in requests {
                                        <li key={r.req_id} className="rounded-lg border pt-3 pb-3 pl-3 pr-3 text-sm">
                                            <div className="flex flex-wrap items-center gap-2">
                                                <span className="font-medium">{pretty(r.need)}</span>
                                                <RequestTag status={r.status} />
                                            </div>
                                            {if r.ngo != "" {
                                                <p className="mt-1">{r.ngo + (" · " + r.ngo_contact if r.ngo_contact != "" else "")}</p>
                                            }}
                                            {if len(r.declined_by) > 0 {
                                                <p className="mt-1 text-xs text-muted-foreground">{"Declined by " + ", ".join(r.declined_by)}</p>
                                            }}
                                            {if r.reason != "" {
                                                <p className="mt-1 text-xs text-muted-foreground">{r.reason}</p>
                                            }}
                                        </li>
                                    }}
                                </ul>
                            }}
                        </CardContent>
                    </Card>

                    {if len(gns) > 0 {
                        <Card>
                            <CardHeader>
                                <div className="flex items-center gap-4">
                                    <IconChip icon={Location01Icon} tone="blue" />
                                    <div className="flex flex-col gap-1">
                                        <CardTitle>Pin the GN division</CardTitle>
                                        <CardDescription>Once you know which GN division the household is in.</CardDescription>
                                    </div>
                                </div>
                            </CardHeader>
                            <CardContent className="flex flex-wrap items-center gap-2">
                                <SelectField id="gn" value={gn} className="min-w-48 flex-1" onChange={lambda (e: ChangeEvent) { gn = e.target.value; }}>
                                    <NativeSelectOption value="">Choose a GN division</NativeSelectOption>
                                    {for g in gns {
                                        <NativeSelectOption key={g} value={g}>{g}</NativeSelectOption>
                                    }}
                                </SelectField>
                                <Button size="sm" className="rounded-full pl-4 pr-4" disabled={saving or gn == ""}
                                    onClick={lambda (e: MouseEvent) { pin_gn(); }}>
                                    Pin
                                </Button>
                            </CardContent>
                        </Card>
                    }}

                    <Card>
                        <CardHeader>
                            <CardTitle>Agent decisions</CardTitle>
                            <CardDescription>Each step taken on this case and what the referee allowed.</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <ol>
                                {for r in inc.trace {
                                    <TraceItem key={str(r.seq)} r={r} stacked={True} />
                                }}
                            </ol>
                        </CardContent>
                    </Card>
                </div>
            </div>
        }}
    </div>
}
