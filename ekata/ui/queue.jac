"""Centre column: the ranked call queue. Every row says why it is where it is."""

import from ekata.views { QueueRow }
import from .atoms { Panel, StatusBadge, VulnerableBadge, people_label }

def:pub QueueItem(
    row: QueueRow,
    selected: bool,
    onSelect: Callable[[str], None]
) -> JsxElement {
    frame: str = "border-border bg-background hover:bg-muted/60";
    if selected {
        frame = "border-primary bg-primary/10 ring-2 ring-primary";
    }

    <li>
        <button
            type="button"
            aria-pressed={selected}
            className={"flex w-full gap-3 rounded-lg border p-3 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary " + frame}
            onClick={lambda (e: MouseEvent) { onSelect(row.inc_id); }}
        >
            <div className="flex w-12 shrink-0 flex-col items-center">
                <span className="text-xs font-semibold uppercase text-muted-foreground">Rank</span>
                <span className="text-3xl font-bold tabular-nums">{f"#{row.rank}"}</span>
            </div>
            <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                    <span className="text-base font-semibold leading-snug">{row.headline}</span>
                </div>
                <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
                    <span>{row.place if row.place != "" else "place unknown"}</span>
                    <span className="font-semibold text-foreground">{people_label(row.headcount)}</span>
                    <span>{"1 message" if row.msg_count == 1 else f"{row.msg_count} messages"}</span>
                    {if row.waiting != "" {
                        <span>{"Waiting " + row.waiting}</span>
                    }}
                </div>
                <div className="mt-2 flex flex-wrap items-center gap-1.5">
                    <StatusBadge status={row.status} />
                    {for v in row.vulnerable {
                        <VulnerableBadge key={v} flag={v} />
                    }}
                </div>
                {if row.reason != "" {
                    <p className="mt-2 text-sm leading-snug">
                        <span className="font-semibold">Why this rank: </span>
                        {row.reason}
                    </p>
                }}
                <p className="mt-1 font-mono text-xs text-muted-foreground">{row.inc_id}</p>
            </div>
        </button>
    </li>
}

def:pub CallQueue(
    rows: list[QueueRow],
    selected: str,
    onSelect: Callable[[str], None]
) -> JsxElement {
    <Panel title="Call queue" note={f"{len(rows)} incidents, most urgent first"}>
        {if len(rows) == 0 {
            <p className="rounded-lg border border-dashed p-4 text-center text-muted-foreground">
                The queue is empty. Incidents appear here as messages arrive.
            </p>
        }}
        <ol className="flex flex-col gap-2">
            {for r in rows {
                <QueueItem key={r.inc_id} row={r} selected={r.inc_id == selected} onSelect={onSelect} />
            }}
        </ol>
    </Panel>
}
