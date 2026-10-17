"""Shared UI pieces for every Ekata portal: plain-language labels, badges,
the portal header, the panel frame and a message row.

Palette (styles/global.css): river blue `primary` for actions, `alert`
(lifebuoy orange) only for people at risk / the next call, `ok` green for
confirmed, `blocked` red for refused or failed. Colour never carries meaning
alone: every badge prints its word.
"""

import type from ekata.views { MsgView }
import from ...components.ui.badge { Badge }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardContent }

# ---------- Label helpers ----------

def:pub pretty(s: str) -> str {
    if s == "" {
        return "";
    }
    low = " ".join(s.split("_")).lower();
    return low[:1].upper() + low[1:];
}

def:pub people_label(n: int) -> str {
    if n <= 0 {
        return "Headcount unknown";
    }
    if n == 1 {
        return "1 person";
    }
    return f"{n} people";
}

def:pub status_label(status: str) -> str {
    labels = {
        "NEW": "New",
        "VERIFYING": "Being checked",
        "CONFIRMED": "Confirmed by phone",
        "CLOSE_PROPOSED": "Ready to close",
        "HANDED_OVER": "Handed over",
        "RESOLVED": "Reached",
        "STALE": "No news for a while"
    };
    return labels.get(status, pretty(status));
}

def:pub kind_label(kind: str) -> str {
    labels = {
        "SOS": "Needs rescue",
        "UPDATE": "Update",
        "OFFER": "Offer of help",
        "APPEAL": "Donation appeal",
        "RUMOUR": "Rumour"
    };
    return labels.get(kind, "Not sorted yet");
}

def:pub verdict_label(verdict: str) -> str {
    labels = {
        "CHECKING": "Being checked",
        "MATCHED": "Matches a real case",
        "UNVERIFIED": "Not verified",
        "SUSPICIOUS": "Suspicious",
        "LIKELY_SCAM": "Likely a scam",
        "CONFIRMED": "Confirmed by an official bulletin",
        "CONTRADICTED": "Official bulletins say this is false",
        "UNCONFIRMED": "No official source yet"
    };
    return labels.get(verdict, pretty(verdict));
}

def:pub request_label(status: str) -> str {
    labels = {
        "REQUESTED": "Waiting for the group",
        "ACCEPTED": "Accepted",
        "DISPATCHED": "On the way",
        "DELIVERED": "Delivered",
        "UNCOVERED": "No group available"
    };
    return labels.get(status, pretty(status));
}

def referee_label(outcome: str) -> str {
    labels = {
        "APPLIED": "Applied",
        "NEEDS_HUMAN": "Needs a person to confirm",
        "BLOCKED": "Blocked by the safety check",
        "NEW_INCIDENT": "Opened a new case",
        "READ_ONLY": "Looked something up",
        "": "Pending"
    };
    return labels.get(outcome, pretty(outcome));
}

def:pub call_outcome_label(outcome: str) -> str {
    labels = {
        "REACHED_CONFIRMED": "Reached and confirmed",
        "NO_ANSWER": "No answer",
        "RESCUED": "Rescued",
        "STILL_IN_NEED": "Still in need"
    };
    return labels.get(outcome, pretty(outcome));
}

# ---------- Tones ----------

def:pub tone_for(kind: str) -> str {
    if kind == "alert" {
        return "border-alert/40 bg-alert-soft text-[#8A3306]";
    }
    if kind == "ok" {
        return "border-ok/30 bg-ok-soft text-ok";
    }
    if kind == "blocked" {
        return "border-blocked/30 bg-blocked-soft text-blocked";
    }
    if kind == "info" {
        return "border-primary/25 bg-accent text-primary";
    }
    return "border-border bg-muted text-muted-foreground";
}

def:pub kind_class(kind: str) -> str {
    if kind == "SOS" {
        return tone_for("alert");
    }
    if kind == "OFFER" {
        return tone_for("ok");
    }
    if kind == "APPEAL" or kind == "UPDATE" {
        return tone_for("info");
    }
    return tone_for("");
}

def:pub status_class(status: str) -> str {
    if status == "CONFIRMED" or status == "RESOLVED" or status == "HANDED_OVER" {
        return tone_for("ok");
    }
    if status == "NEW" {
        return tone_for("alert");
    }
    if status == "VERIFYING" or status == "CLOSE_PROPOSED" {
        return tone_for("info");
    }
    return tone_for("");
}

def:pub referee_class(outcome: str) -> str {
    if outcome == "APPLIED" or outcome == "NEW_INCIDENT" {
        return tone_for("ok");
    }
    if outcome == "NEEDS_HUMAN" {
        return tone_for("alert");
    }
    if outcome == "BLOCKED" {
        return tone_for("blocked");
    }
    return tone_for("");
}

def:pub verdict_class(verdict: str) -> str {
    if verdict == "MATCHED" or verdict == "CONFIRMED" {
        return tone_for("ok");
    }
    if verdict == "LIKELY_SCAM" or verdict == "CONTRADICTED" {
        return tone_for("blocked");
    }
    if verdict == "SUSPICIOUS" {
        return tone_for("alert");
    }
    return tone_for("");
}

def:pub request_class(status: str) -> str {
    if status == "DELIVERED" or status == "ACCEPTED" or status == "DISPATCHED" {
        return tone_for("ok");
    }
    if status == "UNCOVERED" {
        return tone_for("blocked");
    }
    if status == "REQUESTED" {
        return tone_for("alert");
    }
    return tone_for("");
}

# ---------- Badges ----------

def:pub Chip(label: str, tone: str = "") -> JsxElement {
    <Badge
        variant="outline"
        className={"h-auto whitespace-normal rounded-md px-2 py-0.5 text-[13px] font-semibold "
            + (tone if tone != "" else tone_for(""))}
    >
        {label}
    </Badge>
}

def:pub KindBadge(kind: str) -> JsxElement {
    <Chip label={kind_label(kind)} tone={kind_class(kind)}/>
}

def:pub StatusBadge(status: str) -> JsxElement {
    <Chip label={status_label(status)} tone={status_class(status)}/>
}

def:pub RefereeBadge(outcome: str) -> JsxElement {
    <Chip label={referee_label(outcome)} tone={referee_class(outcome)}/>
}

def:pub VerdictBadge(verdict: str) -> JsxElement {
    <Chip label={verdict_label(verdict)} tone={verdict_class(verdict)}/>
}

def:pub RequestBadge(status: str) -> JsxElement {
    <Chip label={request_label(status)} tone={request_class(status)}/>
}

def:pub VulnerableBadge(flag: str) -> JsxElement {
    <Chip label={pretty(flag)} tone={tone_for("alert")}/>
}

# ---------- Portal header (one per portal; no links to other portals) ----------

def:pub PortalHeader(
    portal: str, who: str = "", note: str = "", children: any = None
) -> JsxElement {
    <header className="border-b border-border bg-card">
        <div
            className="mx-auto flex max-w-[1500px] flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3 lg:px-6"
        >
            <a href="#/" className="flex items-center gap-3" aria-label="Ekata home">
                <span
                    className="flex size-9 items-center justify-center rounded-full bg-primary text-[17px] font-bold text-primary-foreground"
                    aria-hidden="true"
                >
                    E
                </span>
                <span className="text-[17px] font-bold tracking-tight">Ekata</span>
            </a>
            <div className="border-l border-border pl-6">
                <p className="text-[17px] font-semibold leading-tight">{portal}</p>
                {if who != "" {
                    <p className="text-[13px] text-muted-foreground">{who}</p>
                }}
            </div>
            {if note != "" {
                <p className="text-[13px] text-muted-foreground">{note}</p>
            }}
            <div className="ml-auto flex flex-wrap items-center gap-2">{children}</div>
        </div>
    </header>
}

# ---------- Panel frame ----------

def:pub Panel(title: str, note: str = "", children: any = None) -> JsxElement {
    <Card
        className="h-full min-h-0 gap-0 overflow-hidden rounded-lg py-0 shadow-none ring-border"
    >
        <CardHeader
            className="flex flex-row items-baseline justify-between gap-2 border-b border-border py-3"
        >
            <CardTitle className="text-[17px] font-semibold">{title}</CardTitle>
            <span className="text-right text-[13px] text-muted-foreground">{note}</span>
        </CardHeader>
        <CardContent className="min-h-0 flex-1 overflow-y-auto py-3">
            {children}
        </CardContent>
    </Card>
}

# ---------- Empty state ----------

def:pub Empty(title: str, hint: str = "") -> JsxElement {
    <div className="rounded-lg border border-dashed border-border px-4 py-8 text-center">
        <p className="text-[15px] font-semibold">{title}</p>
        {if hint != "" {
            <p className="mt-1 text-[13px] text-muted-foreground">{hint}</p>
        }}
    </div>
}

# ---------- One message ----------

def:pub MessageItem(m: MsgView) -> JsxElement {
    <article className="rounded-lg border border-border bg-card p-3">
        <div className="flex flex-wrap items-center gap-2">
            <KindBadge kind={m.kind}/>
            <span className="text-[13px] text-muted-foreground">
                {m.storm_time}{" by "}{m.channel.lower() if m.channel != "" else "web"}
            </span>
        </div>
        <p className="mt-2 whitespace-pre-wrap break-words text-[15px] leading-relaxed">
            {m.text}
        </p>
    </article>
}
