"""Shared UI pieces for the Ekata desk: words-first badges, panel frame, message row.

Colour never carries meaning alone: every badge below prints its word.
"""

import type from ekata.views { MsgView }
import from ...components.ui.badge { Badge }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardContent }

# ---------- Label helpers ----------

def:pub pretty(s: str) -> str {
    if s == "" {
        return "";
    }
    return " ".join(s.split("_"));
}

def:pub people_label(n: int) -> str {
    if n <= 0 {
        return "headcount unknown";
    }
    if n == 1 {
        return "1 person";
    }
    return f"{n} people";
}

def referee_label(outcome: str) -> str {
    if outcome == "APPLIED" {
        return "Referee: applied";
    }
    if outcome == "NEEDS_HUMAN" {
        return "Referee: needs a person";
    }
    if outcome == "BLOCKED" {
        return "Referee: BLOCKED";
    }
    if outcome == "NEW_INCIDENT" {
        return "Referee: new incident";
    }
    if outcome == "" {
        return "Referee: pending";
    }
    return "Referee: " + pretty(outcome);
}

def:pub call_outcome_label(outcome: str) -> str {
    if outcome == "REACHED_CONFIRMED" {
        return "Reached, confirmed";
    }
    if outcome == "NO_ANSWER" {
        return "No answer";
    }
    if outcome == "RESCUED" {
        return "Rescued";
    }
    if outcome == "STILL_IN_NEED" {
        return "Still in need";
    }
    return pretty(outcome);
}

# ---------- Tone classes (each badge also prints a word) ----------

def kind_class(kind: str) -> str {
    if kind == "SOS" {
        return "border-red-500 bg-red-50 text-red-900 dark:border-red-700 dark:bg-red-950 dark:text-red-100";
    }
    if kind == "UPDATE" {
        return "border-sky-500 bg-sky-50 text-sky-900 dark:border-sky-700 dark:bg-sky-950 dark:text-sky-100";
    }
    if kind == "APPEAL" {
        return "border-violet-500 bg-violet-50 text-violet-900 dark:border-violet-700 dark:bg-violet-950 dark:text-violet-100";
    }
    if kind == "RUMOUR" {
        return "border-dashed border-stone-500 bg-stone-100 text-stone-800 dark:bg-stone-900 dark:text-stone-100";
    }
    if kind == "OFFER" {
        return "border-emerald-500 bg-emerald-50 text-emerald-900 dark:border-emerald-700 dark:bg-emerald-950 dark:text-emerald-100";
    }
    return "border-border bg-muted text-muted-foreground";
}

def status_class(status: str) -> str {
    if status == "CONFIRMED" or status == "RESOLVED" {
        return "border-emerald-500 bg-emerald-50 text-emerald-900 dark:border-emerald-700 dark:bg-emerald-950 dark:text-emerald-100";
    }
    if status == "VERIFYING" or status == "CLOSE_PROPOSED" {
        return "border-amber-500 bg-amber-100 text-amber-950 dark:border-amber-600 dark:bg-amber-950 dark:text-amber-100";
    }
    if status == "HANDED_OVER" {
        return "border-indigo-500 bg-indigo-50 text-indigo-900 dark:border-indigo-700 dark:bg-indigo-950 dark:text-indigo-100";
    }
    if status == "STALE" {
        return "border-dashed border-stone-500 bg-stone-100 text-stone-700 dark:bg-stone-900 dark:text-stone-200";
    }
    return "border-sky-500 bg-sky-50 text-sky-900 dark:border-sky-700 dark:bg-sky-950 dark:text-sky-100";
}

def referee_class(outcome: str) -> str {
    if outcome == "APPLIED" {
        return "border-emerald-500 bg-emerald-50 text-emerald-900 dark:border-emerald-700 dark:bg-emerald-950 dark:text-emerald-100";
    }
    if outcome == "NEEDS_HUMAN" {
        return "border-amber-500 bg-amber-100 text-amber-950 dark:border-amber-600 dark:bg-amber-950 dark:text-amber-100";
    }
    if outcome == "BLOCKED" {
        return "border-red-600 bg-red-100 text-red-950 dark:border-red-700 dark:bg-red-950 dark:text-red-100";
    }
    if outcome == "NEW_INCIDENT" {
        return "border-sky-500 bg-sky-50 text-sky-900 dark:border-sky-700 dark:bg-sky-950 dark:text-sky-100";
    }
    return "border-border bg-muted text-muted-foreground";
}

# ---------- Badges ----------

def:pub Chip(label: str, tone: str = "") -> JsxElement {
    <Badge
        variant="outline"
        className={"h-auto whitespace-normal px-2.5 py-0.5 text-sm font-semibold "
            + tone}
    >
        {label}
    </Badge>
}

def:pub KindBadge(kind: str) -> JsxElement {
    <Chip label={kind if kind != "" else "UNSORTED"} tone={kind_class(kind)}/>
}

def:pub StatusBadge(status: str) -> JsxElement {
    <Chip label={pretty(status)} tone={status_class(status)}/>
}

def:pub RefereeBadge(outcome: str) -> JsxElement {
    <Chip label={referee_label(outcome)} tone={referee_class(outcome)}/>
}

def:pub VulnerableBadge(flag: str) -> JsxElement {
    <Chip
        label={"Vulnerable: " + flag}
        tone="border-amber-600 bg-amber-100 text-amber-950 dark:border-amber-600 dark:bg-amber-950 dark:text-amber-100"
    />
}

# ---------- Panel frame ----------

def:pub Panel(title: str, note: str = "", children: any = None) -> JsxElement {
    <Card
        className="h-full min-h-0 gap-0 overflow-hidden border-border/80 py-0 shadow-sm"
    >
        <CardHeader
            className="flex flex-row items-center justify-between gap-2 border-b py-3"
        >
            <CardTitle className="text-lg font-semibold">{title}</CardTitle>
            <span className="text-right text-xs text-muted-foreground">{note}</span>
        </CardHeader>
        <CardContent className="min-h-0 flex-1 overflow-y-auto py-3">
            {children}
        </CardContent>
    </Card>
}

# ---------- One message (inbox row and cited message in the incident card) ----------

def:pub MessageItem(m: MsgView) -> JsxElement {
    <article className="rounded-lg border bg-background p-3">
        <div className="flex flex-wrap items-center gap-2">
            <KindBadge kind={m.kind}/>
            <span className="font-mono text-sm tabular-nums text-muted-foreground">
                {m.storm_time}
            </span>
            <span className="text-sm text-muted-foreground">
                {m.channel}{" "}{m.language}
            </span>
            <span className="ml-auto font-mono text-sm text-muted-foreground">
                {m.msg_id}
            </span>
        </div>
        <p className="mt-2 whitespace-pre-wrap break-words text-base leading-snug">
            {m.text}
        </p>
    </article>
}
