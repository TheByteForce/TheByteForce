"""Ekata store: hub access, ids, lookups, storm clock, normalisers, decisions.

Every graph read and write anchors on root.shared through one EkataHub node;
nothing in the backend touches the caller's root. All demo data hangs off the
hub through Holds edges, so a reset is one sweep.

Backend-owned node types (not in schema.jac): MergeProposal and PendingChange.
"""

import re;
import from ekata.schema {
    EkataHub, Holds, Message, Incident, Decision, About, Phone, PersonName, Place,
    PartOf, CallLog, Logged, Appeal, RumourClaim, RefereeOutcome, Bulletin
}
import from ekata.referee {
    RefereeVerdict, r4_status_change, r13_decision_complete
}

# ---------- Backend-owned nodes ----------

# A merge that needs a person: the message sits in its own new incident
# (from_inc) until a desk approves joining inc_id, or rejects.
node MergeProposal {
    has msg_id: str;
    has inc_id: str;
    has from_inc: str = "";
    has score: float = 0.0;
    has reason: str = "";
    has status: str = "PENDING";
    has decided_by: str = "";
    has storm_time: str = "";
}

# A contradicting value (R6): kept beside the incident, never overwriting it.
node PendingChange {
    has inc_id: str;
    has fld: str;
    has old_value: str = "";
    has new_value: str = "";
    has msg_id: str = "";
    has status: str = "OPEN";
    has storm_time: str = "";
}

glob HUB_NAME: str = "ekata";

# ---------- Hub ----------

def find_hub(hub_name: str) -> EkataHub | None {
    hubs = [root.shared -->][?:EkataHub, name == hub_name];
    if len(hubs) > 0 {
        return hubs[0];
    }
    return None;
}

def make_hub(hub_name: str) -> EkataHub {
    created = root.shared ++> EkataHub(name=hub_name);
    return created;
}

def get_hub() -> EkataHub {
    found = find_hub(HUB_NAME);
    if found is not None {
        return found;
    }
    return make_hub(HUB_NAME);
}

# Delete every node the hub holds and reset counters, flags and the clock.
def wipe_hub(hub: EkataHub) {
    for n in [hub ->:Holds:->] {
        del n;
    }
    hub.replay_pos = 0;
    hub.replay_total = 0;
    hub.decision_seq = 0;
    hub.incident_seq = 0;
    hub.message_seq = 0;
    hub.storm_time = "18:00";
    hub.replay_lock = False;
}

# A private, empty hub for tests (never found by get_hub).
def fresh_hub(hub_name: str) -> EkataHub {
    existing = find_hub(hub_name);
    if existing is not None {
        wipe_hub(existing);
        return existing;
    }
    return make_hub(hub_name);
}

# ---------- Ids ----------

def next_decision_seq(hub: EkataHub) -> int {
    hub.decision_seq += 1;
    return hub.decision_seq;
}

def next_incident_id(hub: EkataHub) -> str {
    hub.incident_seq += 1;
    return f"INC-{hub.incident_seq:03d}";
}

def next_message_seq(hub: EkataHub) -> int {
    hub.message_seq += 1;
    return hub.message_seq;
}

def next_msg_id(hub: EkataHub) -> str {
    return f"W-{(hub.message_seq + 1):03d}";
}

# ---------- Lookups ----------

def all_messages(hub: EkataHub) -> list[Message] {
    return [hub ->:Holds:->[?:Message]];
}

def all_incidents(hub: EkataHub) -> list[Incident] {
    return [hub ->:Holds:->[?:Incident]];
}

def find_message(hub: EkataHub, mid: str) -> Message | None {
    ms = [hub ->:Holds:->[?:Message, msg_id == mid]];
    if len(ms) > 0 {
        return ms[0];
    }
    return None;
}

def find_incident(hub: EkataHub, iid: str) -> Incident | None {
    incs = [hub ->:Holds:->[?:Incident, inc_id == iid]];
    if len(incs) > 0 {
        return incs[0];
    }
    return None;
}

def messages_of(inc: Incident) -> list[Message] {
    ms = [inc <-:PartOf:<-[?:Message]];
    return sorted(ms, key=lambda (m: Message) { m.seq; });
}

def incident_of(msg: Message) -> Incident | None {
    incs = [msg ->:PartOf:->[?:Incident]];
    if len(incs) > 0 {
        return incs[0];
    }
    return None;
}

def has_call_log(inc: Incident) -> bool {
    return len([inc <-:Logged:<-[?:CallLog]]) > 0;
}

def is_seeded(hub: EkataHub) -> bool {
    return len([hub ->:Holds:->[?:Bulletin]]) > 0;
}

# R4 gate: change an incident's status only if the referee allows it.
def change_status(inc: Incident, new_status: str) -> RefereeVerdict {
    v = r4_status_change(new_status, has_call_log(inc));
    if v.outcome != RefereeOutcome.BLOCKED {
        inc.status = new_status;
    }
    return v;
}

def open_pending(hub: EkataHub, iid: str) -> list[PendingChange] {
    return [hub ->:Holds:->[?:PendingChange, inc_id == iid, status == "OPEN"]];
}

def pending_headcount(hub: EkataHub, iid: str) -> int {
    best = 0;
    for p in open_pending(hub, iid) {
        if p.fld == "headcount" {
            n = to_int(p.new_value);
            if n > best {
                best = n;
            }
        }
    }
    return best;
}

def all_proposals(hub: EkataHub) -> list[MergeProposal] {
    return [hub ->:Holds:->[?:MergeProposal]];
}

def to_int(s: str) -> int {
    digits = re.findall(r"\d+", s);
    if len(digits) == 0 {
        return 0;
    }
    return int(digits[0]);
}

# ---------- Storm clock ----------

# Storm nights run 18:00 to 02:00, so an hour before 12 counts as after midnight.
def storm_minutes(t: str) -> int {
    nums = re.findall(r"\d+", t);
    if len(nums) < 2 {
        return 0;
    }
    h = int(nums[0]);
    m = int(nums[1]);
    if h < 12 {
        h += 24;
    }
    return h * 60 + m;
}

def storm_diff(later: str, earlier: str) -> int {
    if later == "" or earlier == "" {
        return 0;
    }
    d = storm_minutes(later) - storm_minutes(earlier);
    if d < 0 {
        return 0;
    }
    return d;
}

def fmt_minutes(mins: int) -> str {
    if mins < 60 {
        return f"{mins} min";
    }
    return f"{mins // 60} h {(mins % 60):02d} min";
}

def later_of(a: str, b: str) -> str {
    if a == "" {
        return b;
    }
    if b == "" {
        return a;
    }
    if storm_minutes(b) > storm_minutes(a) {
        return b;
    }
    return a;
}

def advance_clock(hub: EkataHub, t: str) {
    hub.storm_time = later_of(hub.storm_time, t);
}

# ---------- Normalisers ----------

glob NAME_TITLES: list[str] = [
    "mr", "mrs", "ms", "miss", "dr", "rev", "sir", "madam", "mister", "aunty", "uncle"
];

glob PLACE_DROP: list[str] = ["no", "num", "number", "the", "at", "in", "near", "of", "house"];

glob PLACE_MAP: dict[str, str] = {
    "rd": "road", "mawatha": "road", "mw": "road", "st": "street", "ln": "lane",
    "ave": "avenue", "jn": "junction"
};

glob ROAD_WORDS: list[str] = [
    "road", "lane", "street", "avenue", "path", "junction", "mawatha", "rd", "st", "ln"
];

# One canonical local form: 10 characters starting with 0 (the literal X of the
# synthetic numbers is kept). Anything that does not look like a number gives "".
def normalise_phone(raw: str) -> str {
    s = raw.strip().upper();
    s = re.sub(r"[\s\-\.\(\)]", "", s);
    if s.startswith("+94") {
        s = "0" + s[3:];
    } elif s.startswith("0094") {
        s = "0" + s[4:];
    } elif s.startswith("94") and len(s) == 11 {
        s = "0" + s[2:];
    } elif (not s.startswith("0")) and len(s) == 9 {
        s = "0" + s;
    }
    if re.fullmatch(r"0\d[\dX]\d{7}", s) is None {
        return "";
    }
    return s;
}

def phone_display(canon: str) -> str {
    if len(canon) != 10 {
        return canon;
    }
    return canon[0:3] + "-" + canon[3:6] + "-" + canon[6:];
}

# Every phone-looking number in free text, normalised and de-duplicated.
def phones_in_text(text: str) -> list[str] {
    found: list[str] = [];
    hits = re.findall(r"(?:\+94|0094|\b94|\b0)[\s\-]?(7[0-9Xx])[\s\-]?(\d{3})[\s\-]?(\d{4})", text);
    for h in hits {
        canon = normalise_phone("0" + h[0] + h[1] + h[2]);
        if canon != "" and canon not in found {
            found.append(canon);
        }
    }
    return found;
}

def normalise_name(raw: str) -> str {
    s = re.sub(r"[^\w\s]", " ", raw.lower());
    toks = [t for t in s.split() if t != "" and t not in NAME_TITLES];
    return " ".join(toks);
}

def name_tokens(canon: str) -> list[str] {
    return [t for t in canon.split() if t != ""];
}

def is_full_name(canon: str) -> bool {
    return len(name_tokens(canon)) >= 2;
}

def surname_of(canon: str) -> str {
    toks = name_tokens(canon);
    if len(toks) < 2 {
        return "";
    }
    last = toks[len(toks) - 1];
    if len(last) < 3 {
        return "";
    }
    return last;
}

def title_case(s: str) -> str {
    return " ".join([w.capitalize() for w in s.split()]);
}

def normalise_place(raw: str) -> str {
    s = re.sub(r"[^\w\s]", " ", raw.lower());
    out: list[str] = [];
    for t in s.split() {
        if t in PLACE_DROP {
            continue;
        }
        out.append(PLACE_MAP.get(t, t));
    }
    return " ".join(out);
}

# True when one place description contains the other (so "temple road" fits
# "14 temple road mawanella"). Empty never matches.
def place_compatible(a: str, b: str) -> bool {
    ta = set(a.split());
    tb = set(b.split());
    if len(ta) == 0 or len(tb) == 0 {
        return False;
    }
    return ta.issubset(tb) or tb.issubset(ta);
}

def area_level(place_text: str) -> str {
    for t in normalise_place(place_text).split() {
        if t in ROAD_WORDS {
            return "ROAD";
        }
    }
    return "VILLAGE";
}

# Household place names are "<house or landmark>|<road or village>", normalised.
def household_key(house: str, area: str) -> str {
    return normalise_place(house) + "|" + normalise_place(area);
}

def household_compatible(a: str, b: str) -> bool {
    pa = a.split("|");
    pb = b.split("|");
    if len(pa) < 2 or len(pb) < 2 {
        return a == b;
    }
    if pa[0] == "" or pa[0] != pb[0] {
        return False;
    }
    if pa[1] == "" or pb[1] == "" {
        return True;
    }
    return place_compatible(pa[1], pb[1]);
}

def household_display(key: str) -> str {
    parts = key.split("|");
    if len(parts) < 2 {
        return key;
    }
    if parts[1] == "" {
        return title_case(parts[0]);
    }
    return title_case(parts[0]) + ", " + title_case(parts[1]);
}

# ---------- Identifier nodes (shared across messages) ----------

def ensure_phone(hub: EkataHub, canon: str) -> Phone {
    found = [hub ->:Holds:->[?:Phone, number == canon]];
    for p in found {
        if p.number == canon {
            return p;
        }
    }
    p = Phone(number=canon);
    hub +>:Holds:+> p;
    return p;
}

def ensure_person(hub: EkataHub, canonical: str, display: str) -> PersonName {
    for p in [hub ->:Holds:->[?:PersonName]] {
        if p.canonical == canonical {
            return p;
        }
    }
    p = PersonName(canonical=canonical, display=display if display != "" else title_case(canonical));
    hub +>:Holds:+> p;
    return p;
}

def ensure_place(hub: EkataHub, name: str, level: str) -> Place {
    for p in [hub ->:Holds:->[?:Place]] {
        if p.name == name and p.level == level {
            return p;
        }
    }
    p = Place(name=name, level=level);
    hub +>:Holds:+> p;
    return p;
}

# Road- or village-level place. A new description that contains (or is
# contained in) an existing one reuses its node, so "Temple Road" and
# "Temple Road, Mawanella" share a node. A bare road word never matches.
def ensure_area(hub: EkataHub, name: str, level: str) -> Place {
    specific = [t for t in name.split() if t not in ROAD_WORDS];
    for p in [hub ->:Holds:->[?:Place]] {
        if p.level == "HOUSEHOLD" {
            continue;
        }
        if p.name == name {
            return p;
        }
        if len(specific) > 0 and place_compatible(p.name, name) {
            return p;
        }
    }
    p = Place(name=name, level=level);
    hub +>:Holds:+> p;
    return p;
}

# Reuses an existing household place when the house matches and the road or
# village text is compatible, so one household is one node.
def ensure_household(hub: EkataHub, house: str, area: str) -> Place {
    key = household_key(house, area);
    for p in [hub ->:Holds:->[?:Place]] {
        if p.level == "HOUSEHOLD" and household_compatible(p.name, key) {
            return p;
        }
    }
    p = Place(name=key, level="HOUSEHOLD");
    hub +>:Holds:+> p;
    return p;
}

# ---------- Decisions (R13: every step is recorded) ----------

def log_decision(
    hub: EkataHub,
    agent: str,
    action: str,
    reason: str,
    outcome: str,
    storm_time: str,
    targets: list[Message | Incident | Appeal | RumourClaim | CallLog | MergeProposal],
    confidence: float = 0.0,
    model: str = "",
    target_label: str = ""
) -> Decision {
    why = reason;
    if r13_decision_complete(agent, action, reason, outcome).outcome == RefereeOutcome.BLOCKED {
        why = reason if reason != "" else "(no reason recorded)";
    }
    d = Decision(
        seq=next_decision_seq(hub),
        agent=agent if agent != "" else "unknown",
        action=action if action != "" else "step",
        reason=why,
        confidence=confidence,
        model=model,
        outcome=outcome if outcome != "" else "APPLIED",
        storm_time=storm_time,
        target=target_label
    );
    hub +>:Holds:+> d;
    for t in targets {
        d +>:About:+> t;
    }
    return d;
}
