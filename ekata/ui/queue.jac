"""Officer queue: the Next call hero sentence, then a dense list of the rest."""

import type from ekata.views { QueueRow }
import from ...components.ui.button { Button }
import from .atoms { StatusBadge, VulnerableBadge, people_label, pretty }

def:pub call_sentence(row: QueueRow) -> str {
    who = people_label(row.headcount) if row.headcount > 0 else "People (headcount not known)";
    s = who + " somewhere we still need to confirm";
    if row.place != "" {
        joiner = " " if row.place.lower().startswith("near") else " at ";
        s = who + joiner + row.place;
    }
    if len(row.vulnerable) > 0 {
        flags = [pretty(v).lower() for v in row.vulnerable];
        s = s + ", including " + (" and ".join(flags) if len(flags) <= 2 else ", ".join(flags));
    }
    if row.waiting != "" {
        s = s + f", waiting {row.waiting}";
    }
    return s;
}

def:pub NextCall(row: QueueRow, selected: bool, onSelect: Callable[[str], None]) -> JsxElement {
    <section
        aria-label="Next call"
        className="rounded-lg border border-border border-l-[6px] border-l-alert bg-card p-5"
    >
        <p className="text-[15px] font-semibold text-muted-foreground">Next call</p>
        <p className="mt-1 text-[28px] font-bold leading-tight">{call_sentence(row)}</p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
            <StatusBadge status={row.status}/>
            {for v in row.vulnerable {
                <VulnerableBadge key={v} flag={v}/>
            }}
            <span className="text-[13px] text-muted-foreground">
                {"1 message" if row.msg_count == 1 else f"{row.msg_count} messages"}
            </span>
        </div>
        {if row.reason != "" {
            <p className="mt-2 text-[15px] leading-snug">{row.reason}</p>
        }}
        <div className="mt-4">
            <Button
                className="h-11 px-5 text-[15px]"
                disabled={selected}
                onClick={lambda (e: MouseEvent) { onSelect(row.inc_id); }}
            >
                {"Case is open" if selected else "Open this case"}
            </Button>
        </div>
    </section>
}

def:pub QueueItem(
    row: QueueRow, position: int, selected: bool, onSelect: Callable[[str], None]
) -> JsxElement {
    frame: str = "border-border bg-card hover:bg-muted";
    if selected {
        frame = "border-primary bg-accent";
    }
    <li>
        <button
            type="button"
            aria-pressed={selected}
            className={"flex w-full gap-3 rounded-lg border px-3 py-2.5 text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary "
                + frame}
            onClick={lambda (e: MouseEvent) { onSelect(row.inc_id); }}
        >
            <span
                className="w-7 shrink-0 pt-0.5 text-[21px] font-bold tabular-nums text-muted-foreground"
            >
                {str(position)}
            </span>
            <span className="min-w-0 flex-1">
                <span className="block text-[15px] font-semibold leading-snug">
                    {call_sentence(row)}
                </span>
                <span className="mt-1.5 flex flex-wrap items-center gap-1.5">
                    <StatusBadge status={row.status}/>
                    {for v in row.vulnerable {
                        <VulnerableBadge key={v} flag={v}/>
                    }}
                </span>
                {if row.reason != "" {
                    <span className="mt-1 block text-[13px] text-muted-foreground">
                        {row.reason}
                    </span>
                }}
            </span>
        </button>
    </li>
}

def:pub OfficerQueue(
    rows: list[QueueRow], selected: str, onSelect: Callable[[str], None]
) -> JsxElement {
    if len(rows) == 0 {
        return
            <div className="rounded-lg border border-dashed border-border bg-card px-4 py-10 text-center">
                <p className="text-[17px] font-semibold">No one is waiting in this division</p>
                <p className="mt-1 text-[13px] text-muted-foreground">
                    New calls for help appear here as soon as they arrive.
                </p>
            </div>;
    }
    <div className="flex flex-col gap-4">
        <NextCall
            row={rows[0]}
            selected={rows[0].inc_id == selected}
            onSelect={onSelect}
        />
        {if len(rows) > 1 {
            <section aria-label="Waiting after that">
                <h2 className="mb-2 text-[17px] font-semibold">
                    {f"Waiting after that ({len(rows) - 1})"}
                </h2>
                <ol className="flex flex-col gap-2">
                    {for (i, r) in enumerate(rows) {
                        if i > 0 {
                            <QueueItem
                                key={r.inc_id}
                                row={r}
                                position={i + 1}
                                selected={r.inc_id == selected}
                                onSelect={onSelect}
                            />
                        }
                    }}
                </ol>
            </section>
        }}
    </div>
}
