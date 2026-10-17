"""Officer queue: the next call on a hero card, then the rest as a quiet list."""

import type from ekata.views { QueueRow }
import from ...components.ui.button { Button }
import from .atoms { StatusBadge, VulnerableBadge, people_label, pretty }

def:pub call_sentence(row: QueueRow) -> str {
    who = people_label(row.headcount) if row.headcount > 0 else "A household";
    s = who + ", place not confirmed yet";
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

# The ranker's reason in plain words: flags and waiting time are already shown.
def:pub plain_reason(reason: str) -> str {
    out: list[str] = [];
    for part in reason.split(";") {
        p = part.strip();
        low = p.lower();
        if p == "" or low.endswith("flagged") or low.startswith("waiting") {
            continue;
        }
        if "floor" in low {
            out = out + ["Kept at the top because vulnerable people are waiting"];
        } else {
            out = out + [p[:1].upper() + p[1:]];
        }
    }
    return ". ".join(out);
}

def:pub NextCall(row: QueueRow, selected: bool, onSelect: Callable[[str], None]) -> JsxElement {
    <section
        aria-label="Next call"
        className="rounded-xl border border-border border-l-4 border-l-alert bg-card p-6"
    >
        <p className="text-[14px] font-semibold text-alert">Next call</p>
        <p className="mt-1.5 text-[24px] font-semibold leading-snug tracking-tight">{call_sentence(row)}</p>
        <div className="mt-4 flex flex-wrap items-center gap-2">
            <StatusBadge status={row.status}/>
            {for v in row.vulnerable {
                <VulnerableBadge key={v} flag={v}/>
            }}
            <span className="text-[13px] text-muted-foreground">
                {"1 message" if row.msg_count == 1 else f"{row.msg_count} messages"}
            </span>
        </div>
        {if plain_reason(row.reason) != "" {
            <p className="mt-3 text-[15px] leading-snug text-muted-foreground">{plain_reason(row.reason)}</p>
        }}
        <div className="mt-5">
            <Button
                className="h-11 bg-[#0E3550] px-5 text-[15px] text-white hover:bg-[#0E3550]/90"
                onClick={lambda (e: MouseEvent) { onSelect(row.inc_id); }}
            >
                Open this case
            </Button>
        </div>
    </section>
}

def:pub QueueItem(
    row: QueueRow, position: int, selected: bool, onSelect: Callable[[str], None]
) -> JsxElement {
    <li className="border-b border-border last:border-0">
        <button
            type="button"
            aria-pressed={selected}
            className={"flex w-full gap-4 px-5 py-4 text-left transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-primary "
                + ("bg-muted" if selected else "")}
            onClick={lambda (e: MouseEvent) { onSelect(row.inc_id); }}
        >
            <span className="w-6 shrink-0 text-[15px] font-semibold tabular-nums text-muted-foreground">
                {str(position)}
            </span>
            <span className="min-w-0 flex-1">
                <span className="block text-[15px] font-semibold leading-snug">
                    {call_sentence(row)}
                </span>
                <span className="mt-2 flex flex-wrap items-center gap-1.5">
                    <StatusBadge status={row.status}/>
                    {for v in row.vulnerable {
                        <VulnerableBadge key={v} flag={v}/>
                    }}
                </span>
                {if plain_reason(row.reason) != "" {
                    <span className="mt-1.5 block text-[13px] text-muted-foreground">
                        {plain_reason(row.reason)}
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
            <div className="rounded-xl border border-border bg-card px-5 py-14 text-center">
                <p className="text-[17px] font-semibold">No one is waiting in this division</p>
                <p className="mt-1 text-[15px] text-muted-foreground">
                    New calls for help appear here as soon as they arrive.
                </p>
            </div>;
    }
    <div className="flex flex-col gap-6">
        <NextCall
            row={rows[0]}
            selected={rows[0].inc_id == selected}
            onSelect={onSelect}
        />
        {if len(rows) > 1 {
            <section aria-label="Waiting after that">
                <h2 className="mb-3 text-[16px] font-semibold">
                    {f"Waiting after that ({len(rows) - 1})"}
                </h2>
                <ol className="overflow-hidden rounded-xl border border-border bg-card">
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
