"""Case panel: one incident with its evidence, the places an officer can act
(pin the GN division, ask a relief group, log a call, settle proposals).
"""

import type from ekata.views { IncidentView }
import type from ekata.portal { RequestView }
import from .brief { BriefPanel }
import from ekata.api { decide_merge, log_call, claim_incident, resolve_change }
import from ekata.portal_api { set_gn, request_resource }
import from ...components.ui.button { Button }
import from .atoms {
    MessageItem,
    StatusBadge,
    VulnerableBadge,
    RefereeBadge,
    RequestBadge,
    Chip,
    people_label,
    call_outcome_label,
    pretty
}

def:pub CasePanel(
    inc: IncidentView | None,
    requests: list[RequestView],
    gns: list[str],
    kinds: list[str],
    officer: str,
    loading: bool,
    onSelect: Callable[[str], None],
    onChanged: Callable[[IncidentView | None], None],
    onRefresh: Callable[[], None]
) -> JsxElement {
    has outcome: str = "";
    has note: str = "";
    has gnChoice: str = "";
    has saving: bool = False;
    has err: str = "";
    has flash: str = "";

    async def decide(msgId: str, incId: str, approve: bool) -> None {
        if saving {
            return;
        }
        saving = True;
        err = "";
        flash = "";
        try {
            iv = await decide_merge(msgId, incId, approve, officer);
            flash = "Merge approved." if approve else "Merge rejected.";
            onChanged(iv);
        } except Exception as ex {
            err = "Could not record the decision: " + str(ex);
        }
        saving = False;
    }

    async def submit_call(incId: str) -> None {
        if saving or outcome == "" {
            return;
        }
        saving = True;
        err = "";
        flash = "";
        try {
            iv = await log_call(incId, outcome, officer, note.strip());
            flash = f"Call logged: {call_outcome_label(outcome)}.";
            outcome = "";
            note = "";
            onChanged(iv);
        } except Exception as ex {
            err = "Could not log the call: " + str(ex);
        }
        saving = False;
    }

    async def claim(iid: str, release: bool) -> None {
        try {
            onChanged(await claim_incident(iid, officer, release));
            err = "";
        } except Exception as ex {
            err = str(ex);
        }
    }

    async def review(iid: str, field: str, accept: bool) -> None {
        try {
            onChanged(await resolve_change(iid, field, officer, accept));
            err = "";
        } except Exception as ex {
            err = str(ex);
        }
    }

    async def pin(iid: str) -> None {
        if gnChoice == "" or saving {
            return;
        }
        saving = True;
        err = "";
        flash = "";
        try {
            ok = await set_gn(iid, gnChoice, officer);
            if ok {
                flash = f"Pinned to {gnChoice}.";
                gnChoice = "";
                onRefresh();
            } else {
                err = "That GN division could not be pinned.";
            }
        } except Exception as ex {
            err = "Could not pin the GN division: " + str(ex);
        }
        saving = False;
    }

    async def ask(iid: str, need: str) -> None {
        if saving {
            return;
        }
        saving = True;
        err = "";
        flash = "";
        try {
            r = await request_resource(iid, need, officer);
            if r is None {
                err = "No request was created.";
            } else {
                rv: RequestView = r;
                if rv.ngo != "" {
                    flash = f"Asked {rv.ngo} for {pretty(need).lower()}.";
                } else {
                    flash = f"No group can supply {pretty(need).lower()} right now.";
                }
            }
            onRefresh();
        } except Exception as ex {
            err = "Could not send the request: " + str(ex);
        }
        saving = False;
    }

    if inc is None {
        return
            <section className="rounded-lg border border-dashed border-border bg-card px-4 py-10 text-center">
                <p className="text-[15px] text-muted-foreground">
                    {"Opening the case..."
                        if loading
                        else "Pick a case from the queue to see what was said and what you can do."}
                </p>
            </section>;
    }

    iid: str = inc.inc_id;
    h2: str = "text-[17px] font-semibold";
    field: str = "h-10 rounded-md border border-border bg-background px-2 text-[15px] focus-visible:outline-2 focus-visible:outline-primary";

    <section
        aria-label="Case"
        className="rounded-lg border border-border bg-card p-4 lg:sticky lg:top-4 lg:max-h-[calc(100dvh-2rem)] lg:overflow-y-auto"
    >
        <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={inc.status}/>
            {for v in inc.vulnerable {
                <VulnerableBadge key={v} flag={v}/>
            }}
            {if inc.claimed_by != "" {
                <Chip label={"Claimed by " + inc.claimed_by} tone="border-primary/25 bg-accent text-primary"/>
            }}
        </div>
        <h2 className="mt-2 text-[21px] font-bold leading-snug">
            {people_label(inc.headcount)}
            {" at "}
            {inc.place if inc.place != "" else "a place we still need to confirm"}
        </h2>
        {if inc.summary != "" {
            <p className="mt-1 text-[15px] leading-snug">{inc.summary}</p>
        }}
        {if len(inc.needs) > 0 {
            <div className="mt-2 flex flex-wrap items-center gap-1.5">
                {for n in inc.needs {
                    <Chip key={n} label={"Needs " + n.lower()}/>
                }}
            </div>
        }}
        {if flash != "" {
            <p
                role="status"
                className="mt-3 rounded-md border border-ok/30 bg-ok-soft p-2 text-[15px] font-semibold text-ok"
            >
                {flash}
            </p>
        }}
        {if err != "" {
            <p
                role="alert"
                className="mt-3 rounded-md border border-blocked/30 bg-blocked-soft p-2 text-[15px] font-semibold text-blocked"
            >
                {err}
            </p>
        }}
        <div className="mt-3 flex flex-wrap gap-2">
            <Button
                disabled={inc.claimed_by != "" and inc.claimed_by != officer}
                onClick={lambda (e: MouseEvent) { claim(iid, False); }}
            >
                {"Claimed by you" if inc.claimed_by == officer else "Claim before calling"}
            </Button>
            {if inc.claimed_by == officer {
                <Button
                    variant="outline"
                    onClick={lambda (e: MouseEvent) { claim(iid, True); }}
                >
                    Release
                </Button>
            }}
        </div>
        {for p in inc.pending {
            <div
                key={p.field + p.msg_id}
                className="mt-4 rounded-lg border border-primary/40 bg-accent p-3"
            >
                <p className="text-[15px] font-semibold">
                    {f"A new message changes {pretty(p.field).lower()} from {p.old_value} to {p.new_value}"}
                </p>
                <p className="mt-0.5 text-[13px] text-muted-foreground">
                    Check by phone before you accept a correction.
                </p>
                <div className="mt-2 flex flex-wrap gap-2">
                    <Button onClick={lambda (e: MouseEvent) { review(iid, p.field, True); }}>
                        Accept after the call
                    </Button>
                    <Button
                        variant="outline"
                        onClick={lambda (e: MouseEvent) { review(iid, p.field, False); }}
                    >
                        Keep the old value
                    </Button>
                </div>
            </div>
        }}
        <div className="mt-5">
            <BriefPanel
                key={iid + str(len(inc.messages)) + str(len(inc.calls))}
                incId={iid}
            />
        </div>
        <div className="mt-5">
            <h3 className={h2}>Pin the GN division</h3>
            <p className="text-[13px] text-muted-foreground">
                The router only knows the DS division. Choose the village area once you know it.
            </p>
            <div className="mt-2 flex flex-wrap items-center gap-2">
                <label className="sr-only" htmlFor="gn-pick">GN division</label>
                <select
                    id="gn-pick"
                    value={gnChoice}
                    className={field + " min-w-48 flex-1"}
                    onChange={lambda (e: ChangeEvent) { gnChoice = e.target.value; }}
                >
                    <option value="">Choose a GN division</option>
                    {for g in gns {
                        <option key={g} value={g}>{g}</option>
                    }}
                </select>
                <Button
                    disabled={saving or gnChoice == ""}
                    onClick={lambda (e: MouseEvent) { pin(iid); }}
                >
                    Pin
                </Button>
            </div>
        </div>
        <div className="mt-5">
            <h3 className={h2}>Ask a relief group</h3>
            <div className="mt-2 flex flex-wrap gap-2">
                {for k in kinds {
                    <Button
                        key={k}
                        variant="outline"
                        disabled={saving}
                        onClick={lambda (e: MouseEvent) { ask(iid, k); }}
                    >
                        {"Ask for " + pretty(k).lower()}
                    </Button>
                }}
            </div>
            {if len(requests) == 0 {
                <p className="mt-2 text-[13px] text-muted-foreground">
                    No requests sent for this case yet.
                </p>
            }}
            <ul className="mt-2 flex flex-col gap-2">
                {for r in requests {
                    <li key={r.req_id} className="rounded-lg border border-border bg-background p-3">
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="text-[15px] font-semibold">{pretty(r.need)}</span>
                            <RequestBadge status={r.status}/>
                        </div>
                        <p className="mt-1 text-[15px]">
                            {r.ngo if r.ngo != "" else "No group is assigned yet"}
                            {if r.ngo_contact != "" {
                                <span className="text-muted-foreground">{", call " + r.ngo_contact}</span>
                            }}
                        </p>
                        {if len(r.declined_by) > 0 {
                            <p className="mt-0.5 text-[13px] font-semibold text-blocked">
                                {"Declined by " + ", ".join(r.declined_by)
                                    + (", sent to " + r.ngo if r.ngo != "" else "")}
                            </p>
                        }}
                        {if r.reason != "" {
                            <p className="mt-0.5 text-[13px] text-muted-foreground">{r.reason}</p>
                        }}
                    </li>
                }}
            </ul>
        </div>
        <div className="mt-5">
            <h3 className={h2}>Log a call</h3>
            <form
                className="mt-2 rounded-lg border border-border bg-background p-3"
                onSubmit={lambda (e: FormEvent) {
                    e.preventDefault();
                    submit_call(iid);
                }}
            >
                <div className="flex flex-wrap items-end gap-3">
                    <label className="flex flex-col gap-1 text-[13px] font-semibold">
                        What happened
                        <select
                            value={outcome}
                            className={field + " font-normal"}
                            onChange={lambda (e: ChangeEvent) { outcome = e.target.value; }}
                        >
                            <option value="">Choose an outcome</option>
                            <option value="REACHED_CONFIRMED">Reached and confirmed</option>
                            <option value="NO_ANSWER">No answer</option>
                            <option value="RESCUED">Rescued</option>
                            <option value="STILL_IN_NEED">Still in need</option>
                        </select>
                    </label>
                    <label className="flex min-w-40 flex-1 flex-col gap-1 text-[13px] font-semibold">
                        Note, if any
                        <input
                            type="text"
                            value={note}
                            className={field + " font-normal"}
                            onChange={lambda (e: ChangeEvent) { note = e.target.value; }}
                        />
                    </label>
                    <Button type="submit" disabled={saving or outcome == ""}>
                        {"Saving..." if saving else "Log call"}
                    </Button>
                </div>
            </form>
            {if len(inc.calls) > 0 {
                <ul className="mt-2 flex flex-col gap-1">
                    {for (i, c) in enumerate(inc.calls) {
                        <li
                            key={str(i)}
                            className="flex flex-wrap items-center gap-x-2 rounded-md border border-border px-3 py-2 text-[15px]"
                        >
                            <span className="tabular-nums text-muted-foreground">{c.storm_time}</span>
                            <span className="font-semibold">{call_outcome_label(c.outcome)}</span>
                            <span className="text-muted-foreground">{c.desk}</span>
                            {if c.note != "" {
                                <span className="basis-full">{c.note}</span>
                            }}
                        </li>
                    }}
                </ul>
            }}
        </div>
        {if len(inc.proposals) > 0 {
            <div className="mt-5">
                <h3 className={h2}>Messages that may belong here</h3>
                <ul className="mt-2 flex flex-col gap-2">
                    {for p in inc.proposals {
                        <li
                            key={p.msg_id + ">" + p.inc_id}
                            className="rounded-lg border border-border bg-background p-3"
                        >
                            <div className="flex flex-wrap items-center gap-2">
                                <span className="text-[15px] font-semibold">
                                    {f"Message {p.msg_id} and case {p.inc_id}"}
                                </span>
                                <span className="ml-auto">
                                    <RefereeBadge outcome={p.outcome}/>
                                </span>
                            </div>
                            {if p.reason != "" {
                                <p className="mt-1 text-[13px] text-muted-foreground">{p.reason}</p>
                            }}
                            {if p.outcome == "NEEDS_HUMAN" {
                                <div className="mt-2 flex flex-wrap gap-2">
                                    <Button
                                        disabled={saving}
                                        onClick={lambda (e: MouseEvent) { decide(p.msg_id, p.inc_id, True); }}
                                    >
                                        Same case, merge
                                    </Button>
                                    <Button
                                        variant="outline"
                                        disabled={saving}
                                        onClick={lambda (e: MouseEvent) { decide(p.msg_id, p.inc_id, False); }}
                                    >
                                        Different case
                                    </Button>
                                </div>
                            }}
                        </li>
                    }}
                </ul>
            </div>
        }}
        {if len(inc.candidates) > 0 {
            <div className="mt-5">
                <h3 className={h2}>Similar cases</h3>
                <ul className="mt-2 flex flex-col gap-2">
                    {for c in inc.candidates {
                        <li
                            key={c.inc_id}
                            className="flex items-start gap-2 rounded-lg border border-dashed border-border p-3"
                        >
                            <ul className="flex-1 list-disc pl-5 text-[15px] leading-snug">
                                {for rs in c.reasons {
                                    <li key={rs}>{rs}</li>
                                }}
                            </ul>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={lambda (e: MouseEvent) { onSelect(c.inc_id); }}
                            >
                                Open
                            </Button>
                        </li>
                    }}
                </ul>
            </div>
        }}
        <div className="mt-5">
            <h3 className={h2}>{f"What was said ({len(inc.messages)})"}</h3>
            {if len(inc.messages) == 0 {
                <p className="text-[13px] text-muted-foreground">
                    No messages are attached to this case yet.
                </p>
            }}
            <div className="mt-2 flex flex-col gap-2">
                {for m in inc.messages {
                    <MessageItem key={m.msg_id} m={m}/>
                }}
            </div>
        </div>
    </section>
}
