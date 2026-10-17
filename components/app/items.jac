"""List items shared by several pages: a message, a queue row, a trace row."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Location01Icon, UserGroupIcon, Message01Icon, Clock01Icon, ArrowRight01Icon
}
import type from ekata.views { MsgView, QueueRow, TraceRow }
import from ekata.api { trace_since }
import from .tags { Tag, KindTag, StatusTag, RefereeTag, VulnerableTag }
import from .labels { people_label, place_label, plural, channel_label, pretty, agent_name }
import from ...lib.utils { cn }

def:pub MessageItem(m: MsgView) -> JsxElement {
    <article className="rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4">
        <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <KindTag kind={m.kind} />
            <span>{channel_label(m.channel)}</span>
            {if m.language != "" {
                <span className="uppercase">{m.language}</span>
            }}
            <span className="ml-auto font-mono text-xs tabular-nums">
                {m.storm_time}
                {" · "}
                {m.msg_id}
            </span>
        </div>
        <p className="mt-2 whitespace-pre-wrap break-words text-sm leading-relaxed">{m.text}</p>
    </article>
}

# One incident in a ranked list. The whole row links to the incident page.
def:pub QueueItem(row: QueueRow, compact: bool = False) -> JsxElement {
    <li>
        <Link
            to={"/officer/cases/" + row.inc_id}
            className="group flex gap-4 rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4 transition-colors hover:bg-muted/50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
        >
            <div className="flex w-10 shrink-0 flex-col items-center">
                <span className="text-xs text-muted-foreground">Rank</span>
                <span className="text-2xl font-semibold tabular-nums">{str(row.rank)}</span>
            </div>
            <div className="min-w-0 flex-1">
                <p className={cn("font-medium leading-snug", "line-clamp-1" if compact else "line-clamp-2")}>{row.headline}</p>
                <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
                    <span className="inline-flex items-center gap-1">
                        <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-4" />
                        {place_label(row.place)}
                    </span>
                    <span className="inline-flex items-center gap-1">
                        <HugeiconsIcon icon={UserGroupIcon} strokeWidth={2} className="size-4" />
                        {people_label(row.headcount)}
                    </span>
                    {if not compact {
                        <span className="inline-flex items-center gap-1">
                            <HugeiconsIcon icon={Message01Icon} strokeWidth={2} className="size-4" />
                            {plural(row.msg_count, "message", "messages")}
                        </span>
                    }}
                    {if row.waiting != "" {
                        <span className="inline-flex items-center gap-1">
                            <HugeiconsIcon icon={Clock01Icon} strokeWidth={2} className="size-4" />
                            {"Waiting " + row.waiting}
                        </span>
                    }}
                </div>
                <div className="mt-2 flex flex-wrap items-center gap-2">
                    <StatusTag status={row.status} />
                    {for v in row.vulnerable {
                        <VulnerableTag key={v} flag={v} />
                    }}
                </div>
                {if not compact and row.reason != "" {
                    <p className="mt-2 text-sm text-muted-foreground">
                        <span className="font-medium text-foreground">Why this rank: </span>
                        {row.reason}
                    </p>
                }}
            </div>
            <HugeiconsIcon
                icon={ArrowRight01Icon}
                strokeWidth={2}
                className="mt-1 size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
            />
        </Link>
    </li>
}

# Every decision after `after`, oldest first. trace_since pages 50 at a time.
async def:pub fetch_trace(after: int, t: int) -> list[TraceRow] {
    out: list[TraceRow] = [];
    cursor: int = after;
    while True {
        rows = await trace_since(cursor, t);
        out = out + rows;
        if len(rows) < 50 {
            break;
        }
        cursor = rows[len(rows) - 1].seq;
    }
    return out;
}

def:pub TraceItem(r: TraceRow, stacked: bool = False) -> JsxElement {
    is_incident: bool = r.target.startswith("INC-");
    <li className={cn("flex flex-col gap-1 border-b pt-3 pb-3 last:border-b-0", "" if stacked else "sm:flex-row sm:items-start sm:gap-4")}>
        <span className="w-24 shrink-0 font-mono text-xs tabular-nums text-muted-foreground">
            {f"#{r.seq} · {r.storm_time}"}
        </span>
        <div className="min-w-0 flex-1 text-sm">
            <div className="flex flex-wrap items-center gap-2">
                <Tag label={agent_name(r.agent)} tone="slate" />
                <span className="font-medium">{pretty(r.action)}</span>
                {if is_incident {
                    <Link to={"/officer/cases/" + r.target} className="font-mono text-xs text-primary underline-offset-4 hover:underline">
                        {r.target}
                    </Link>
                } elif r.target != "" {
                    <span className="font-mono text-xs text-muted-foreground">{r.target}</span>
                }}
                {if r.outcome != "" {
                    <RefereeTag outcome={r.outcome} />
                }}
            </div>
            {if r.reason != "" {
                <p className="mt-1 text-muted-foreground">{r.reason}</p>
            }}
        </div>
        {if r.confidence > 0.0 {
            <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                {f"{round(r.confidence * 100)}% confidence"}
            </span>
        }}
    </li>
}
