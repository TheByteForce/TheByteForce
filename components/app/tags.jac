"""Status tags: a neutral outline badge with a small colour dot.

The word always carries the meaning; the dot is only a quick visual cue.
"""

import from ..ui.badge { Badge }
import from ...lib.utils { cn }
import from .labels { pretty, referee_label }

glob DOT: dict[str, str] = {
    "red": "bg-red-500",
    "orange": "bg-orange-500",
    "amber": "bg-amber-500",
    "blue": "bg-blue-500",
    "green": "bg-emerald-500",
    "violet": "bg-violet-500",
    "slate": "bg-zinc-400"
};

def:pub dot_class(tone: str) -> str {
    return DOT[tone] or "bg-zinc-400";
}

def:pub Tag(label: str, tone: str = "slate", className: str = "") -> JsxElement {
    <Badge variant="outline" className={cn("h-6 gap-1.5 rounded-full bg-background pl-2.5 pr-2.5 font-medium", className)}>
        <span aria-hidden="true" className={cn("size-1.5 shrink-0 rounded-full", dot_class(tone))}></span>
        {label}
    </Badge>
}

def:pub kind_tone(kind: str) -> str {
    if kind == "SOS" {
        return "red";
    }
    if kind == "UPDATE" {
        return "blue";
    }
    if kind == "OFFER" {
        return "green";
    }
    if kind == "APPEAL" {
        return "violet";
    }
    return "slate";
}

def:pub status_tone(status: str) -> str {
    if status == "CONFIRMED" or status == "RESOLVED" {
        return "green";
    }
    if status == "VERIFYING" or status == "CLOSE_PROPOSED" {
        return "amber";
    }
    if status == "HANDED_OVER" {
        return "violet";
    }
    if status == "STALE" {
        return "slate";
    }
    return "blue";
}

def:pub referee_tone(outcome: str) -> str {
    if outcome == "APPLIED" {
        return "green";
    }
    if outcome == "NEEDS_HUMAN" {
        return "amber";
    }
    if outcome == "BLOCKED" {
        return "red";
    }
    if outcome == "NEW_INCIDENT" {
        return "blue";
    }
    return "slate";
}

def:pub level_tone(level: int) -> str {
    if level >= 5 {
        return "red";
    }
    if level == 4 {
        return "orange";
    }
    if level == 3 {
        return "amber";
    }
    if level == 2 {
        return "blue";
    }
    return "green";
}

def:pub verdict_tone(verdict: str) -> str {
    if verdict == "LIKELY_SCAM" or verdict == "CONTRADICTED" {
        return "red";
    }
    if verdict == "SUSPICIOUS" {
        return "orange";
    }
    if verdict == "MATCHED" or verdict == "CONFIRMED" {
        return "green";
    }
    if verdict == "CHECKING" {
        return "blue";
    }
    return "slate";
}

def:pub request_tone(status: str) -> str {
    if status == "UNCOVERED" {
        return "red";
    }
    if status == "REQUESTED" {
        return "amber";
    }
    if status == "ACCEPTED" or status == "DISPATCHED" {
        return "blue";
    }
    if status == "DELIVERED" {
        return "green";
    }
    return "slate";
}

def:pub request_label(status: str) -> str {
    if status == "REQUESTED" {
        return "Waiting for a group";
    }
    if status == "ACCEPTED" {
        return "Accepted";
    }
    if status == "DISPATCHED" {
        return "On the way";
    }
    if status == "DELIVERED" {
        return "Delivered";
    }
    if status == "UNCOVERED" {
        return "No group can cover";
    }
    return pretty(status);
}

def:pub RequestTag(status: str) -> JsxElement {
    <Tag label={request_label(status)} tone={request_tone(status)} />
}

def:pub KindTag(kind: str) -> JsxElement {
    <Tag label={kind if kind != "" else "Unsorted"} tone={kind_tone(kind)} />
}

def:pub StatusTag(status: str) -> JsxElement {
    <Tag label={pretty(status)} tone={status_tone(status)} />
}

def:pub RefereeTag(outcome: str) -> JsxElement {
    <Tag label={"Referee: " + referee_label(outcome)} tone={referee_tone(outcome)} />
}

def:pub VulnerableTag(flag: str) -> JsxElement {
    <Tag label={"Vulnerable: " + flag} tone="amber" />
}

def:pub LevelTag(level: int) -> JsxElement {
    <Tag label={f"Level {level}"} tone={level_tone(level)} />
}

def:pub VerdictTag(verdict: str) -> JsxElement {
    <Tag label={pretty(verdict)} tone={verdict_tone(verdict)} />
}
