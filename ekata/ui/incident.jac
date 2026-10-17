"""Right column: the selected incident, its evidence, merge proposals and call log."""

import type from ekata.views { IncidentView }
import from .brief { BriefPanel }
import from ekata.api { decide_merge, log_call, claim_incident, resolve_change }
import from ...components.ui.button { Button }
import from .atoms {
    Panel,
    MessageItem,
    StatusBadge,
    VulnerableBadge,
    RefereeBadge,
    Chip,
    people_label,
    call_outcome_label,
    pretty
}

def:pub IncidentCard(
    inc: IncidentView | None,
    loading: bool,
    desk: str,
    onDesk: Callable[[str], None],
    onSelect: Callable[[str], None],
    onChanged: Callable[[IncidentView | None], None]
) -> JsxElement {
    has outcome: str = "";
    has note: str = "";
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
            iv = await decide_merge(msgId, incId, approve, desk);
            verb = "Approved" if approve else "Rejected";
            flash = f"{verb} merge of {msgId} into {incId} as {desk}.";
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
            iv = await log_call(incId, outcome, desk, note.strip());
            flash = f"Call logged: {call_outcome_label(outcome)} ({desk}).";
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
            onChanged(await claim_incident(iid, desk, release));
            err = "";
        } except Exception as ex {
            err = str(ex);
        }
    }
    async def review(iid: str, field: str, accept: bool) -> None {
        try {
            onChanged(await resolve_change(iid, field, desk, accept));
            err = "";
        } except Exception as ex {
            err = str(ex);
        }
    }

    if inc is None {
        return
            <Panel title="Incident">
                <p
                    className="rounded-lg border border-dashed p-4 text-center text-muted-foreground"
                >
                    {"Loading incident..."
                        if loading
                        else "Select an incident in the call queue to see its evidence, merge proposals and call log."}
                </p>
            </Panel>;
    }

    iid: str = inc.inc_id;

    <Panel title="Incident" note={iid}>
        <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={inc.status}/>
            <span className="text-lg font-semibold">{people_label(inc.headcount)}</span>
            <span className="text-base text-muted-foreground">
                {inc.place if inc.place != "" else "place unknown"}
            </span>
            <label className="ml-auto flex items-center gap-2 text-sm font-semibold">
                Acting as
                <select
                    value={desk}
                    className="h-9 rounded-md border bg-background px-2 text-base font-normal"
                    onChange={lambda (e: ChangeEvent) { onDesk(e.target.value); }}
                >
                    <option value="Desk A">Desk A</option>
                    <option value="Desk B">Desk B</option>
                    <option value="Desk C">Desk C</option>
                </select>
            </label>
        </div>
        {if inc.summary != "" {
            <p className="mt-2 text-base leading-snug">{inc.summary}</p>
        }}
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
            {for v in inc.vulnerable {
                <VulnerableBadge key={v} flag={v}/>
            }}
            {for n in inc.needs {
                <Chip
                    key={n}
                    label={"Needs: " + n}
                    tone="border-border bg-secondary text-secondary-foreground"
                />
            }}
            {if inc.claimed_by != "" {
                <Chip
                    label={"Claimed by " + inc.claimed_by}
                    tone="border-indigo-500 bg-indigo-50 text-indigo-900 dark:bg-indigo-950 dark:text-indigo-100"
                />
            }}
        </div>
        {if flash != "" {
            <p
                role="status"
                className="sticky top-0 z-10 mt-3 rounded-md border border-emerald-600 bg-emerald-50 p-2 text-sm font-semibold text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100"
            >
                {flash}
            </p>
        }}
        {if err != "" {
            <p
                role="alert"
                className="sticky top-0 z-10 mt-3 rounded-md border border-red-600 bg-red-50 p-2 text-sm font-semibold text-red-900 dark:bg-red-950 dark:text-red-100"
            >
                {err}
            </p>
        }}
        <h3 className="mt-4 text-base font-semibold">
            {f"Cited messages ({len(inc.messages)})"}
        </h3>
        {if len(inc.messages) == 0 {
            <p className="text-sm text-muted-foreground">
                No messages are attached to this incident yet.
            </p>
        }}
        <div className="mt-1 flex flex-col gap-2">
            {for m in inc.messages {
                <MessageItem key={m.msg_id} m={m}/>
            }}
        </div>
        <h3 className="mt-4 text-base font-semibold">
            {f"Candidate incidents ({len(inc.candidates)})"}
        </h3>
        {if len(inc.candidates) == 0 {
            <p className="text-sm text-muted-foreground">
                No other incident shares details with this one.
            </p>
        }}
        <ul className="mt-1 flex flex-col gap-2">
            {for c in inc.candidates {
                <li
                    key={c.inc_id}
                    className="rounded-lg border border-dashed bg-background p-3"
                >
                    <div className="flex items-center gap-2">
                        <span className="font-mono text-sm font-semibold">
                            {c.inc_id}
                        </span>
                        <Button
                            variant="outline"
                            size="sm"
                            className="ml-auto"
                            onClick={lambda (e: MouseEvent) { onSelect(c.inc_id); }}
                        >
                            Open
                        </Button>
                    </div>
                    <ul className="mt-1 list-disc pl-5 text-sm leading-snug">
                        {for rs in c.reasons {
                            <li key={rs}>{rs}</li>
                        }}
                    </ul>
                </li>
            }}
        </ul>
        <h3 className="mt-4 text-base font-semibold">
            {f"Merge proposals ({len(inc.proposals)})"}
        </h3>
        {if len(inc.proposals) == 0 {
            <p className="text-sm text-muted-foreground">
                No merge proposals for this incident.
            </p>
        }}
        <ul className="mt-1 flex flex-col gap-2">
            {for p in inc.proposals {
                <li
                    key={p.msg_id + ">" + p.inc_id}
                    className="rounded-lg border bg-background p-3"
                >
                    <div className="flex flex-wrap items-center gap-2">
                        <span className="font-mono text-sm">{p.msg_id}</span>
                        <span aria-hidden="true">{"→"}</span>
                        <span className="font-mono text-sm">{p.inc_id}</span>
                        <span className="text-sm text-muted-foreground">
                            {f"score {p.score:.2f}"}
                        </span>
                        <span className="ml-auto">
                            <RefereeBadge outcome={p.outcome}/>
                        </span>
                    </div>
                    {if p.reason != "" {
                        <p className="mt-1 text-sm leading-snug">
                            <span className="font-semibold">Why: </span>
                            {p.reason}
                        </p>
                    }}
                    {if p.outcome == "NEEDS_HUMAN" {
                        <div className="mt-2 flex flex-wrap items-center gap-2">
                            <Button
                                disabled={saving}
                                onClick={lambda (e: MouseEvent) { decide(
                                    p.msg_id, p.inc_id, True
                                ); }}
                            >
                                Approve merge
                            </Button>
                            <Button
                                variant="outline"
                                disabled={saving}
                                onClick={lambda (e: MouseEvent) { decide(
                                    p.msg_id, p.inc_id, False
                                ); }}
                            >
                                Reject merge
                            </Button>
                            <span
                                className="text-sm font-semibold text-amber-900 dark:text-amber-200"
                            >
                                A person must decide
                            </span>
                        </div>
                    }}
                </li>
            }}
        </ul>
        <div className="mt-4 flex gap-2">
            <Button
                disabled={inc.claimed_by != "" and inc.claimed_by != desk}
                onClick={lambda (e: MouseEvent) { claim(iid, False); }}
            >
                Claim before calling
            </Button>
            {if inc.claimed_by == desk {
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
                className="mt-3 rounded border border-amber-600 p-3"
            >
                <p className="font-semibold">
                    {p.field + ": " + p.old_value + " → " + p.new_value}
                </p>
                <p className="text-sm">
                    Verify by phone before accepting a correction.
                </p>
                <Button
                    onClick={lambda (e: MouseEvent) { review(iid, p.field, True); }}
                >
                    Accept after call
                </Button>
                <Button
                    variant="outline"
                    onClick={lambda (e: MouseEvent) { review(iid, p.field, False); }}
                >
                    Keep previous value
                </Button>
            </div>
        }}
        <BriefPanel
            key={iid + str(len(inc.messages)) + str(len(inc.calls))}
            incId={iid}
        />
        <h3 className="mt-4 text-base font-semibold">Log a call</h3>
        <form
            className="mt-1 rounded-lg border bg-muted/40 p-3"
            onSubmit={lambda (e: FormEvent) {
                e.preventDefault();
                submit_call(iid);
            }}
        >
            <div className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-sm font-semibold">
                    Outcome
                    <select
                        value={outcome}
                        className="h-9 rounded-md border bg-background px-2 text-base font-normal"
                        onChange={lambda (e: ChangeEvent) { outcome = e.target.value; }}
                    >
                        <option value="">Choose an outcome</option>
                        <option value="REACHED_CONFIRMED">Reached, confirmed</option>
                        <option value="NO_ANSWER">No answer</option>
                        <option value="RESCUED">Rescued</option>
                        <option value="STILL_IN_NEED">Still in need</option>
                    </select>
                </label>
                <label
                    className="flex min-w-40 flex-1 flex-col gap-1 text-sm font-semibold"
                >
                    Note (optional)
                    <input
                        type="text"
                        value={note}
                        className="h-9 rounded-md border bg-background px-2 text-base font-normal"
                        onChange={lambda (e: ChangeEvent) { note = e.target.value; }}
                    />
                </label>
                <Button type="submit" disabled={saving or outcome == ""}>
                    {"Saving..." if saving else f"Log call as {desk}"}
                </Button>
            </div>
        </form>
        <h3 className="mt-4 text-base font-semibold">
            {f"Past calls ({len(inc.calls)})"}
        </h3>
        {if len(inc.calls) == 0 {
            <p className="text-sm text-muted-foreground">No calls logged yet.</p>
        }}
        <ul className="mt-1 flex flex-col gap-1">
            {for (i, c) in enumerate(inc.calls) {
                <li
                    key={str(i)}
                    className="flex flex-wrap items-center gap-2 rounded-md border bg-background px-3 py-2 text-sm"
                >
                    <span className="font-mono tabular-nums text-muted-foreground">
                        {c.storm_time}
                    </span>
                    <span className="font-semibold">
                        {call_outcome_label(c.outcome)}
                    </span>
                    <span className="text-muted-foreground">{c.desk}</span>
                    {if c.note != "" {
                        <span className="basis-full">{c.note}</span>
                    }}
                </li>
            }}
        </ul>
    </Panel>
}
