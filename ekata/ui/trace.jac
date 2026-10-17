"""Bottom strip: the agent trace, newest first, plus the live graph link."""

import type from ekata.views { TraceRow }
import from .atoms { Chip, RefereeBadge, pretty }

def:pub TraceItem(
    r: TraceRow, knownIds: list[str], onSelect: Callable[[str], None]
) -> JsxElement {
    <li
        className="flex flex-wrap items-center gap-x-2 gap-y-1 border-b px-4 py-2 text-sm last:border-b-0"
    >
        <span className="w-10 shrink-0 font-mono text-xs text-muted-foreground">
            {f"#{r.seq}"}
        </span>
        <span className="w-14 shrink-0 font-mono tabular-nums text-muted-foreground">
            {r.storm_time}
        </span>
        <Chip
            label={r.agent + (" / " + r.model if r.model != "" else "")}
            tone="border-border bg-secondary text-secondary-foreground uppercase tracking-wide"
        />
        <span aria-hidden="true">{"→"}</span>
        <span className="font-semibold">{pretty(r.action)}</span>
        {if r.target != "" and r.target in knownIds {
            <button
                type="button"
                className="rounded border px-1.5 font-mono text-xs hover:bg-muted"
                onClick={lambda (e: MouseEvent) { onSelect(r.target); }}
            >
                {r.target}
            </button>
        } elif r.target != "" {
            <span className="rounded border border-dashed px-1.5 font-mono text-xs">
                {r.target}
            </span>
        } }
        {if r.reason != "" {
            <span aria-hidden="true">{"→"}</span>
            <span className="min-w-0">{r.reason}</span>
        }}
        {if r.outcome != "" {
            <span aria-hidden="true">{"→"}</span>
            <RefereeBadge outcome={r.outcome}/>
        }}
        {if r.confidence > 0.0 {
            <span className="ml-auto text-xs text-muted-foreground">
                {f"confidence {round(r.confidence * 100)}%"}
            </span>
        }}
    </li>
}

def:pub TraceStrip(
    rows: list[TraceRow], knownIds: list[str], onSelect: Callable[[str], None]
) -> JsxElement {
    <section
        aria-label="Agent trace"
        className="flex min-h-0 flex-col border-t bg-card lg:h-40 lg:shrink-0"
    >
        <div
            className="flex flex-wrap items-center justify-between gap-2 border-b px-4 py-2 lg:px-6"
        >
            <h2 className="text-lg font-semibold">
                Agent trace
                <span
                    className="ml-2 hidden text-xs font-normal text-muted-foreground md:inline"
                >
                    Newest decisions · cited reasons · referee outcomes
                </span>
            </h2>
            <a
                href="/graph"
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-md border px-3 py-1 text-sm font-semibold hover:bg-muted"
            >
                Open live graph (new tab)
            </a>
        </div>
        <div className="max-h-72 min-h-0 flex-1 overflow-y-auto lg:max-h-none">
            {if len(rows) == 0 {
                <p className="p-4 text-muted-foreground">
                    No agent decisions yet. Every merge, check and block will be listed here.
                </p>
            }}
            <ol>
                {for r in rows {
                    <TraceItem
                        key={str(r.seq)}
                        r={r}
                        knownIds={knownIds}
                        onSelect={onSelect}
                    />
                }}
            </ol>
        </div>
    </section>
}
