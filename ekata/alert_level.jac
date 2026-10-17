"""Ekata alert levels: a 5-level evacuation-style call urgency per incident.

Level 5 life at risk, 4 rescue needed, 3 vulnerable first, 2 verify or
confirm, 1 closed. Deterministic: no model is involved.
"""

import from ekata.schema { EkataHub, Incident }
import from ekata.store { all_incidents, storm_diff, fmt_minutes }
import from ekata.referee { OPEN_STATUSES }

glob ALERT_VULNERABLE: list[str] = ["elderly", "child", "disability", "pregnant", "medical"];
glob ALERT_RESCUE_NEEDS: list[str] = ["rescue", "boat"];
glob ALERT_LONG_WAIT: int = 60;

obj AlertInfo {
    has level: int;
    has label: str;
    has action: str;
    has reason: str;
}

obj AlertRow {
    has inc_id: str;
    has level: int;
    has label: str;
    has action: str;
    has reason: str;
    has priority: float;
}

def alert_for(inc: Incident, storm_now: str) -> AlertInfo {
    if inc.status == "RESOLVED" or inc.status == "HANDED_OVER" {
        return AlertInfo(level=1, label="Level 1 · Closed", action="No call needed",
            reason=f"Status {inc.status.lower()}");
    }
    if inc.status == "CLOSE_PROPOSED" {
        return AlertInfo(level=2, label="Level 2 · Confirm by call",
            action="One call to confirm the rescue", reason="Rescue reported, closing proposed");
    }
    flags = [f for f in inc.vulnerable if f in ALERT_VULNERABLE];
    rescue = [n for n in inc.needs if n in ALERT_RESCUE_NEEDS];
    waited = storm_diff(storm_now, inc.first_seen);
    has_rescue = len(rescue) > 0;
    has_flag = len(flags) > 0;
    flag_txt = ", ".join(flags);
    need_txt = ", ".join(rescue);
    if "medical" in flags {
        return AlertInfo(level=5, label="Level 5 · Life at risk now", action="Call immediately",
            reason="Medical emergency flagged");
    }
    if has_flag and has_rescue and waited >= ALERT_LONG_WAIT {
        return AlertInfo(level=5, label="Level 5 · Life at risk now", action="Call immediately",
            reason=f"{flag_txt} + {need_txt}, waiting {fmt_minutes(waited)}");
    }
    if has_rescue {
        return AlertInfo(level=4, label="Level 4 · Rescue needed", action="Call next",
            reason=f"Needs {need_txt}");
    }
    if has_flag {
        return AlertInfo(level=3, label="Level 3 · Vulnerable first", action="Call before others",
            reason=f"Vulnerable: {flag_txt}");
    }
    return AlertInfo(level=2, label="Level 2 · Verify", action="Verify by call when free",
        reason="No rescue need or vulnerable flag reported");
}

def alert_board(hub: EkataHub) -> list[AlertRow] {
    rows: list[AlertRow] = [];
    for inc in all_incidents(hub) {
        if inc.status not in OPEN_STATUSES {
            continue;
        }
        a = alert_for(inc, hub.storm_time);
        rows.append(AlertRow(inc_id=inc.inc_id, level=a.level, label=a.label,
            action=a.action, reason=a.reason, priority=inc.priority));
    }
    return sorted(rows, key=lambda (r: AlertRow) { (r.level, r.priority); }, reverse=True);
}
