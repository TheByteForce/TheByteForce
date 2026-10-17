"""Intake agent (A1): message text -> typed SosReport.

The model (the fast pool, temperature 0) only extracts and classifies; every
exact rule stays in plain Jac: phone normalisation, the HOUSEHOLD place rule,
the vulnerable-tag vocabulary, name canonicalisation, regex capture of phones,
bank accounts and links. If the model is unavailable or returns something
unusable, extract_report_rules() (pure regex and keywords) answers instead, so
the desk never loses a message. intake_run_info() tells the caller which engine
and model produced the last report, for the decision trail.
"""

import re;
import from ekata.replay_cache { read_cached, record_cached }
import from ekata.schema { SosReport, MsgKind, PlaceLevel, PersonMention }
import from ekata.ai.models { fast, call_log }

# The pool this agent calls. A plain glob alias so tests can swap in MockLLM.
glob intake_model: any = fast;

glob ALLOWED_VULNERABLE: list[str] = ["elderly", "child", "medical", "disability", "pregnant"],
     ROAD_WORDS: str = "Road|Rd|Lane|Mawatha|Street|St|Place|Avenue|Watta|Mw",
     NAME_STOP: list[str] = [
         "Help", "Please", "Pls", "We", "Our", "My", "The", "This", "That", "Urgent", "Water", "Flood",
         "Boat", "Road", "Rd", "Lane", "Town", "Street", "Mawatha", "Estate", "Temple", "Ward", "House",
         "No", "Kotmale", "Dam", "Caller", "Hello", "Hi", "Dear", "Sir", "Madam", "There", "Here", "Call",
         "Back", "Mother", "Father", "Grandmother", "Grandfather", "Wife", "Husband", "Son", "Daughter",
         "Relatives", "Update", "Safe", "Rescued", "Share", "Forward", "Breaking", "Kegalle", "Mawanella",
         "Rambukkana", "Aranayake", "Warakapola", "Galigamuwa", "Kolonna", "Ground", "Big", "Small"
     ],
     PHONE_RE: str = r"(?<![0-9A-Za-z])(?:\+94|0094|94|0)[\s\-]?[0-9X]{2}[\s\-]?[0-9X]{3}[\s\-]?[0-9X]{4}(?![0-9A-Za-z])",
     ACCOUNT_RE: str = r"\bSYN-[A-Z0-9]{3,6}-[A-Z0-9]{3,6}\b",
     URL_RE: str = r"(?:https?://|www\.)[^\s,)>]+",
     SINGLISH_WORDS: list[str] = [
         "mama", "api ", "oya", "eka", "ekak", "inne", "inna", "wathura", "wathure", "gedara", "udaw", "udau",
         "karanna", "kiyala", "thiyenawa", "thiyanawa", "pirila", "pirenawa", "amma", "thaththa", "tatta",
         "putha", "duwa", "baya", "ahakas", "kohomada", "denna", "dennama", "wayasai", "nathi", "ona"
     ];

glob NEED_RULES: dict[str, str] = {
    "boat": r"\bboats?\b",
    "rescue": r"\b(?:rescue|evacuat\w*|stuck|trapped|stranded|on the roof|2nd floor|second floor)\b",
    "food": r"\b(?:food|hungry|rations?|meals?)\b",
    "water": r"\b(?:drinking water|no (?:clean |drinking )?water|need water|water supply)\b",
    "medical": r"\b(?:medicine|medication|inhaler|dialysis|doctor|ambulance|insulin|oxygen|first aid)\b",
    "shelter": r"\b(?:shelter|camp)\b"
};

glob last_run: dict[str, str] = {"engine": "", "model": ""};

# ---------- What the model fills in (a draft; plain Jac converts it to SosReport) ----------
# The sem notes only reach the model when the type is declared in this module, so the
# model fills these draft types and draft_to_report() copies them into the shared
# SosReport. The AI schema and the storage schema can then evolve independently.

enum DraftKind: str {
    SOS = "SOS",
    UPDATE = "UPDATE",
    OFFER = "OFFER",
    APPEAL = "APPEAL",
    RUMOUR = "RUMOUR"
}

enum DraftPlace: str {
    HOUSEHOLD = "HOUSEHOLD",
    ROAD = "ROAD",
    VILLAGE = "VILLAGE",
    UNKNOWN = "UNKNOWN"
}

obj DraftName {
    has display: str = "";
    has canonical: str = "";
}

obj ReportDraft {
    has kind: DraftKind = DraftKind.SOS;
    has people_count: int = 0;
    has vulnerable: list[str] = [];
    has needs: list[str] = [];
    has place_text: str = "";
    has place_level: DraftPlace = DraftPlace.UNKNOWN;
    has house_ref: str = "";
    has phones: list[str] = [];
    has names: list[DraftName] = [];
    has language: str = "en";
    has rescued: bool = False;
    has summary: str = "";
    has confidence: float = 0.0;
    has payee_accounts: list[str] = [];
    has urls: list[str] = [];
    has claimed_office: str = "";
    has asks_credentials: list[str] = [];
    has claims_for_names: list[str] = [];
}

sem DraftKind.SOS = "A person or family in danger asking to be rescued or helped. This is the default for a request for help.";
sem DraftKind.UPDATE = "New information about an existing emergency: the people were rescued, are safe, moved, or the situation changed.";
sem DraftKind.OFFER = "Someone offering help (a boat, a vehicle, shelter, supplies) rather than asking for it.";
sem DraftKind.APPEAL = "A fundraising or help appeal that asks the reader for money, a bank deposit, or credentials. Not an SOS from the person in danger.";
sem DraftKind.RUMOUR = "An unverified claim about dams, rivers, rescues or warnings, or a forwarded old photo or chain message. Usually 'share this' content.";
sem DraftPlace.HOUSEHOLD = "Only when the text gives a house number, 'line house N', or a named landmark such as 'near the Bodhi temple'.";
sem DraftPlace.ROAD = "A road or lane is named but no house number or landmark.";
sem DraftPlace.VILLAGE = "Only a town, village or area is named.";
sem DraftPlace.UNKNOWN = "No place is given.";

sem DraftName.display = "The person's name as written in the message.";
sem DraftName.canonical = "Lowercase romanised given name plus family name, the same for every script and spelling, for example 'seelawathie perera' or 'murugan raja'.";

sem ReportDraft.kind = "Message category: SOS, UPDATE, OFFER, APPEAL or RUMOUR.";
sem ReportDraft.people_count = "Total number of people in danger or covered by the message; 0 if not stated.";
sem ReportDraft.vulnerable = "Vulnerable groups present, only from: elderly, child, medical, disability, pregnant. A wheelchair or very old person is elderly; a baby or young child is child; asthma, dialysis, fever or a medical emergency is medical.";
sem ReportDraft.needs = "Short needs such as boat, rescue, food, water, medical, shelter.";
sem ReportDraft.place_text = "The place exactly as the sender wrote it (town, road, house, landmark); empty if none.";
sem ReportDraft.place_level = "How precise the place is: HOUSEHOLD only with a house number, 'line house N' or a named landmark; ROAD for a road only; VILLAGE for a town or area only.";
sem ReportDraft.house_ref = "The house reference as written, for example '14 Hettimulla Road' or 'line house 3 Deraniyagala estate'; empty if none.";
sem ReportDraft.phones = "Phone numbers exactly as written in the message (an X inside a number is a placeholder: keep it).";
sem ReportDraft.names = "Every person named as being in danger, or as the sender or caller. One entry per person.";
sem ReportDraft.language = "Language of the message: en, si (Sinhala script), ta (Tamil script) or singlish (Sinhala in Latin letters).";
sem ReportDraft.rescued = "True when the message says the people have already been rescued or are safe now.";
sem ReportDraft.summary = "One short English line saying who needs what and where, for a duty officer.";
sem ReportDraft.confidence = "0.0 to 1.0, how sure you are about kind and the key facts.";
sem ReportDraft.payee_accounts = "Bank or wallet account numbers the reader is asked to pay into, as written.";
sem ReportDraft.urls = "Web links in the message, as written.";
sem ReportDraft.claimed_office = "The official body or post the sender claims to speak for (for example 'Grama Niladhari' or 'Divisional Secretariat'); empty if none.";
sem ReportDraft.asks_credentials = "Credentials requested FROM THE READER: for example NIC, NIC photo, OTP, bank login. Empty for an ordinary SOS that only gives the sender's own phone number.";
sem ReportDraft.claims_for_names = "For an APPEAL, the canonical lowercase names of the people the appeal says it raises money for; empty otherwise.";

def llm_extract_report(message_text: str, channel: str) -> ReportDraft by intake_model(
    temperature=0.0,
    incl_info={"field_rules": "HOUSEHOLD requires a house number or a named household landmark; a road or village alone is insufficient. Lowercase romanised given and family names must be canonical across Sinhala, Tamil, Singlish and English. Credentials are requests FROM THE READER; never confuse a caller giving their phone with an OTP request. Never invent facts. Vulnerability tags are elderly, child, medical, disability, pregnant. Distinguish an offer from a request and a rumour from an SOS."},
    max_output_retries=2,
    system_prompt="You triage emergency messages from a flood in Sri Lanka for a disaster duty desk. Messages arrive in English, Sinhala script, Tamil script or Singlish. Extract only what the text says; never invent a name, number, place or account. Leave a field empty or 0 when the text does not give it."
);
sem llm_extract_report = "Read one incoming flood-night message (message_text, received over channel) and fill in the structured report for the duty desk.";

def draft_to_report(d: ReportDraft) -> SosReport {
    return SosReport(
        kind=MsgKind(d.kind),
        people_count=d.people_count,
        vulnerable=list(d.vulnerable),
        needs=list(d.needs),
        place_text=d.place_text,
        place_level=PlaceLevel(d.place_level),
        house_ref=d.house_ref,
        phones=list(d.phones),
        names=[PersonMention(display=n.display, canonical=n.canonical) for n in d.names],
        language=d.language,
        rescued=d.rescued,
        summary=d.summary,
        confidence=d.confidence,
        payee_accounts=list(d.payee_accounts),
        urls=list(d.urls),
        claimed_office=d.claimed_office,
        asks_credentials=list(d.asks_credentials),
        claims_for_names=list(d.claims_for_names)
    );
}

# ---------- Deterministic helpers (plain Jac) ----------

"""Normalise a Sri Lankan phone number to one local form (0XXXXXXXXX); a literal X stays."""
def normalise_phone(raw: str) -> str {
    s = re.sub(r"[\s\-\.\(\)]", "", raw).upper();
    if s.startswith("+94") {
        s = "0" + s[3:];
    } elif s.startswith("0094") {
        s = "0" + s[4:];
    } elif s.startswith("94") and len(s) >= 11 {
        s = "0" + s[2:];
    } elif len(s) == 9 and not s.startswith("0") {
        s = "0" + s;
    }
    return s;
}

def _dedupe(items: list[str]) -> list[str] {
    out: list[str] = [];
    for it in items {
        if it != "" and it not in out {
            out.append(it);
        }
    }
    return out;
}

def phones_in(text: str) -> list[str] {
    found = [normalise_phone(m) for m in re.findall(PHONE_RE, text, re.IGNORECASE)];
    return _dedupe(found);
}

def canonical_name(raw: str) -> str {
    return " ".join(re.sub(r"[^\w\s]", " ", raw).lower().split());
}

"""Model name that answered the most recent successful call since call_log had `mark` rows."""
def model_since(mark: int) -> str {
    start = min(mark, len(call_log));
    for i in range(len(call_log) - 1, start - 1, -1) {
        row = call_log[i];
        if row["status"] == "success" {
            return str(row["model"]);
        }
    }
    return "";
}

"""Which engine ('llm' or 'rules') and model produced the last report."""
def intake_run_info -> dict[str, str] {
    return dict(last_run);
}

def _demote_place(rep: SosReport) -> None {
    low = rep.place_text.lower();
    if re.search(r"\b(?:road|rd|lane|mawatha|street|avenue)\b", low) {
        rep.place_level = PlaceLevel.ROAD;
    } elif rep.place_text != "" {
        rep.place_level = PlaceLevel.VILLAGE;
    } else {
        rep.place_level = PlaceLevel.UNKNOWN;
    }
}

"""Apply the exact rules to a model report: the model proposes, plain Jac disposes."""
def finalise_report(rep: SosReport, text: str) -> SosReport {
    rep.phones = _dedupe([normalise_phone(p) for p in rep.phones] + phones_in(text));
    rep.payee_accounts = _dedupe(
        [a.strip() for a in rep.payee_accounts] + re.findall(ACCOUNT_RE, text)
    );
    rep.urls = _dedupe(
        [u.strip().rstrip(".,;") for u in rep.urls]
        + [u.rstrip(".,;") for u in re.findall(URL_RE, text)]
    );
    rep.vulnerable = _dedupe([v.strip().lower() for v in rep.vulnerable if v.strip().lower() in ALLOWED_VULNERABLE]);
    seen: list[str] = [];
    names: list[PersonMention] = [];
    for n in rep.names {
        canon = canonical_name(n.canonical if n.canonical != "" else n.display);
        if canon != "" and canon not in seen {
            seen.append(canon);
            names.append(PersonMention(display=n.display if n.display != "" else canon, canonical=canon));
        }
    }
    rep.names = names;
    rep.claims_for_names = _dedupe([canonical_name(c) for c in rep.claims_for_names]);
    if rep.people_count < 0 {
        rep.people_count = 0;
    }
    rep.confidence = max(0.0, min(1.0, rep.confidence));
    if rep.place_level == PlaceLevel.HOUSEHOLD and rep.house_ref.strip() == "" {
        _demote_place(rep);
    }
    if rep.rescued and rep.kind == MsgKind.SOS {
        rep.kind = MsgKind.UPDATE;
    }
    return rep;
}

# ---------- The agent ----------

def report_data(rep: SosReport) -> dict[str, any] {
    return {"kind": rep.kind.value, "people_count": rep.people_count, "vulnerable": rep.vulnerable, "needs": rep.needs, "place_text": rep.place_text, "place_level": rep.place_level.value, "house_ref": rep.house_ref, "phones": rep.phones, "names": [{"display": x.display, "canonical": x.canonical} for x in rep.names], "language": rep.language, "rescued": rep.rescued, "summary": rep.summary, "confidence": rep.confidence, "payee_accounts": rep.payee_accounts, "urls": rep.urls, "claimed_office": rep.claimed_office, "asks_credentials": rep.asks_credentials, "claims_for_names": rep.claims_for_names};
}

def restore_report(d: any) -> SosReport {
    return SosReport(kind=MsgKind(str(d["kind"])), people_count=int(d["people_count"]), vulnerable=[str(x) for x in d["vulnerable"]], needs=[str(x) for x in d["needs"]], place_text=str(d["place_text"]), place_level=PlaceLevel(str(d["place_level"])), house_ref=str(d["house_ref"]), phones=[str(x) for x in d["phones"]], names=[PersonMention(display=str(x["display"]), canonical=str(x["canonical"])) for x in d["names"]], language=str(d["language"]), rescued=bool(d["rescued"]), summary=str(d["summary"]), confidence=float(d["confidence"]), payee_accounts=[str(x) for x in d["payee_accounts"]], urls=[str(x) for x in d["urls"]], claimed_office=str(d["claimed_office"]), asks_credentials=[str(x) for x in d["asks_credentials"]], claims_for_names=[str(x) for x in d["claims_for_names"]]);
}

def extract_report(text: str, channel: str = "WEB") -> SosReport {
    payload: dict[str, any] = {"text": text, "channel": channel};
    cached: any = read_cached("intake", payload);
    if cached is not None {
        last_run["engine"] = "cached"; last_run["model"] = "cached:" + str(cached["model"]);
        last_run["recorded_at"] = str(cached["recorded_at"]); last_run["error"] = "";
        return restore_report(cached["value"]);
    }
    mark = len(call_log);
    try {
        rep = draft_to_report(llm_extract_report(text, channel));
        last_run["engine"] = "llm";
        last_run["error"] = "";
        last_run["model"] = model_since(mark);
        rep = finalise_report(rep, text);
        record_cached("intake", payload, report_data(rep), last_run["model"]);
        return rep;
    } except Exception as e {
        last_run["engine"] = "rules";
        last_run["error"] = type(e).__name__ + ": " + re.sub(r"AIza[A-Za-z0-9_-]{20,}", "[REDACTED_SECRET]", str(e))[:220];
        last_run["model"] = "rules";
        return extract_report_rules(text, channel);
    }
}

# ---------- Rules fallback: regex and keywords only, no model ----------

def _has(pattern: str, text: str) -> bool {
    return re.search(pattern, text, re.IGNORECASE) is not None;
}

def _detect_language(text: str) -> str {
    if re.search(r"[඀-෿]", text) {
        return "si";
    }
    if re.search(r"[஀-௿]", text) {
        return "ta";
    }
    low = " " + text.lower() + " ";
    hits = len([w for w in SINGLISH_WORDS if w in low]);
    return "singlish" if hits >= 2 else "en";
}

def _rules_kind(text: str) -> tuple[MsgKind, bool] {
    low = text.lower();
    cleaned = re.sub(
        r"\b(?:not|never|no longer|isn't|aren't)\s+(?:yet\s+)?(?:safe|been rescued|rescued)\b|\bunsafe\b|\byet to be rescued\b|\b(?:nobody|no one)\s+(?:has\s+)?(?:been\s+)?rescued\b",
        " ",
        low
    );
    if re.search(r"\b(?:rescued|reached (?:the )?(?:camp|shelter|safety)|(?:we are|we're|all|now|are|is) safe)\b", cleaned) {
        return (MsgKind.UPDATE, True);
    }
    if re.search(r"\b(?:donate|donation|deposit|fund|funds|fundraising|account|nic|otp)\b", low) {
        return (MsgKind.APPEAL, False);
    }
    if re.search(r"\bdam\b|river will|photo", low) {
        return (MsgKind.RUMOUR, False);
    }
    if re.search(r"\bupdate\b", low) {
        return (MsgKind.UPDATE, False);
    }
    if re.search(r"boat (?:is )?available|\bready to\b|can help|can offer|we have a (?:boat|truck|van|tractor)", low) {
        return (MsgKind.OFFER, False);
    }
    return (MsgKind.SOS, False);
}

def _rules_vulnerable(text: str) -> list[str] {
    low = text.lower();
    out: list[str] = [];
    if re.search(r"wheelchair|elderly|bedridden|grand(?:mother|father|ma|pa)|\bold (?:man|woman|lady|people|couple|mother|father)\b|(?<!year )(?<!years )(?<!yrs )(?<!month )(?<!months )(?<!-)\bold\b", low) {
        out.append("elderly");
    }
    if re.search(r"\b(?:baby|infant|child|children|kids?|toddler|daughter|son)\b", low) {
        out.append("child");
    }
    if re.search(r"asthma|dialysis|fever|fainted|diabet|insulin|oxygen|bleeding|injured|unconscious|seizure", low) {
        out.append("medical");
    }
    if re.search(r"disabled|disability|\bblind\b|\bdeaf\b|cannot walk", low) {
        out.append("disability");
    }
    if re.search(r"pregnan", low) {
        out.append("pregnant");
    }
    return out;
}

def _rules_people(text: str) -> int {
    for pat in [
        r"(\d+)\s*(?:people|persons|of us|members|adults|souls|inside|stranded|in the house)",
        r"(?:we are|there are|family of)\s+(\d+)"
    ] {
        m = re.search(pat, text, re.IGNORECASE);
        if m {
            return int(m.group(1));
        }
    }
    return 0;
}

def _rules_names(text: str) -> list[PersonMention] {
    found: list[str] = [];
    cap = r"[A-Z][a-z]+";
    patterns = [
        r"(?:caller|this is|i am|my name is|name is)\s+(" + cap + r"(?:\s+" + cap + r")?)",
        r"(" + cap + r"(?:\s+" + cap + r")?)\s+family",
        r"(?:^|[.,!?\-]\s*)(" + cap + r"\s+" + cap + r")(?=,|\s+here|\.|\s*$)"
    ];
    for pat in patterns {
        flags = re.IGNORECASE if pat.startswith("(?:caller") else 0;
        for m in re.finditer(pat, text, flags) {
            raw = m.group(1).strip();
            parts = raw.split();
            if len(parts) == 0 {
                continue;
            }
            if len([p for p in parts if p.capitalize() in NAME_STOP]) > 0 {
                continue;
            }
            canon = " ".join([p.lower() for p in parts]);
            if canon not in [f for f in found] {
                found.append(canon);
            }
        }
    }
    return [PersonMention(display=" ".join([p.capitalize() for p in c.split()]), canonical=c) for c in found];
}

def _rules_place(text: str) -> tuple[str, PlaceLevel, str] {
    house = "";
    m = re.search(r"\bline\s+house\s+(\d+[A-Za-z]?)(?:[\s,]+((?:[A-Z][A-Za-z]+\s+){1,2}[Ee]state))?", text, re.IGNORECASE);
    if m {
        house = "line house " + m.group(1);
        if m.group(2) {
            house = house + " " + m.group(2).strip();
        }
    }
    road_m = re.search(
        r"(?:\bNo\.?\s*)?(\d+[A-Za-z]?(?:/\d+)?),?\s+((?:[A-Z][a-z]+\s+){1,2}(?:" + ROAD_WORDS + r"))\b\.?",
        text
    );
    if house == "" and road_m {
        house = road_m.group(1) + " " + road_m.group(2).strip();
    }
    landmark = "";
    lm = re.search(r"\bnear (?:the )?([A-Za-z]+ (?:temple|church|mosque|kovil|school|junction|bridge|shop|hospital))", text, re.IGNORECASE);
    if lm {
        landmark = "near the " + lm.group(1);
    }
    road_only = re.search(r"\b((?:[A-Z][a-z]+\s+){1,2}(?:" + ROAD_WORDS + r"))\b", text);
    town = "";
    tm = re.search(r"(?:" + ROAD_WORDS + r"),\s+([A-Z][a-z]+)", text);
    if tm {
        town = tm.group(1);
    } else {
        lead = re.search(r"^\s*([A-Z][a-z]+)[.,]\s", text);
        if lead and lead.group(1) not in NAME_STOP {
            town = lead.group(1);
        }
    }
    ref = house if house != "" else landmark;
    if ref != "" {
        place_text = ref + (", " + town if town != "" else "");
        return (place_text, PlaceLevel.HOUSEHOLD, ref);
    }
    if road_only {
        road = road_only.group(1).strip();
        return (road + (", " + town if town != "" else ""), PlaceLevel.ROAD, "");
    }
    if town != "" {
        return (town, PlaceLevel.VILLAGE, "");
    }
    return ("", PlaceLevel.UNKNOWN, "");
}

def _rules_credentials(text: str) -> list[str] {
    out: list[str] = [];
    if _has(r"\bnic\b|national identity", text) {
        out.append("NIC photo" if _has(r"photo|picture|copy|scan", text) else "NIC");
    }
    if _has(r"\botp\b|one[- ]time (?:pin|password|code)", text) {
        out.append("OTP");
    }
    if _has(r"bank login|online banking|internet banking|bank password|\bpassword\b|\bcvv\b|card number", text) {
        out.append("bank login");
    }
    return out;
}

def _rules_office(text: str) -> str {
    m = re.search(r"(Grama Niladhari|GN officer|Divisional Secretariat|DS office|Disaster Management Centre|\bDMC\b|Red Cross|Police|Army|Navy|Ministry of [A-Z][a-z]+)", text);
    return m.group(1) if m else "";
}

def _rules_needs(text: str, kind: MsgKind) -> list[str] {
    out: list[str] = [];
    for label in NEED_RULES.keys() {
        if _has(NEED_RULES[label], text) {
            out.append(label);
        }
    }
    if len(out) == 0 and kind == MsgKind.SOS {
        out.append("rescue");
    }
    return out;
}

"""No-model fallback for extract_report: regex and keyword rules over the same SosReport shape."""
def extract_report_rules(text: str, channel: str = "WEB") -> SosReport {
    (kind, rescued) = _rules_kind(text);
    (place_text, level, house_ref) = _rules_place(text);
    creds = _rules_credentials(text);
    family_for = [
        canonical_name(x)
        for x in re.findall(r"(?:for|help|support|behalf of)\s+(?:the\s+)?([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)(?:'s)?\s+family", text)
    ];
    is_appeal = kind == MsgKind.APPEAL;
    one_line = " ".join(text.split())[:140];
    return SosReport(
        kind=kind,
        people_count=_rules_people(text),
        vulnerable=_rules_vulnerable(text),
        needs=_rules_needs(text, kind),
        place_text=place_text,
        place_level=level,
        house_ref=house_ref,
        phones=phones_in(text),
        names=_rules_names(text),
        language=_detect_language(text),
        rescued=rescued,
        summary=one_line,
        confidence=0.4,
        payee_accounts=_dedupe(re.findall(ACCOUNT_RE, text)),
        urls=_dedupe([u.rstrip(".,;") for u in re.findall(URL_RE, text)]),
        claimed_office=_rules_office(text) if is_appeal else "",
        asks_credentials=creds,
        claims_for_names=_dedupe(family_for) if is_appeal else []
    );
}
