"""GN household register: who lives in each Grama Niladhari division, read
beside tonight's messages.

The register is reference data registered before the storm (synthetic for the
demo): households, their residents, and who needs help to leave. It hangs off
its own RegisterHub on root.shared, so load_demo never wipes it and the world
graph's lookups stay fast. It is seeded once per REGISTER_VERSION.

Linking is read-only and never touches the merge pipeline. It uses the same
evidence tiers as blocking, on SOS and UPDATE messages only:
  heard     STRONG: a registered phone, or the registered house (same number
            or landmark on the same road) together with a resident's full name
  possible  MEDIUM: the house alone, or a resident's full name alone; shown
            for the officer to check by phone, never linked
A shared surname or a road alone is never a link (R1).
"""

import os;
import json;
import from ekata.schema {
    EkataHub, Holds, Message, Incident, Phone, PersonName, Place, HasPhone, Names, At, PartOf,
    CallLog
}
import from ekata.store {
    normalise_phone, phone_display, normalise_name, normalise_place, is_full_name,
    storm_minutes, ROAD_WORDS, log_decision
}
import from ekata.portal { calls_of, requests_of, VERIFIED_OUTCOMES }

glob LINK_KINDS: list[str] = ["SOS", "UPDATE"];

glob REGISTER_NAME: str = "ekata-gn-register",
     REGISTER_VERSION: str = "v1",
     REGISTER_FILE: str = "gn_register.json";

# ---------- Register nodes ----------

node RegisterHub {
    has name: str = "ekata-gn-register";
    has version: str = "";
}

node GnArea {
    has gn: str;
    has ds: str = "";
    has district: str = "";
    has officer: str = "";
}

node RegHousehold {
    has hh_id: str;
    has house: str = "";
    has road: str = "";
    has phones: list[str] = [];
    has note: str = "";
}

node Resident {
    has name: str;
    has canonical: str = "";
    has age: int = 0;
    has needs: list[str] = [];
    has evac_help: bool = False;
    has note: str = "";
}

edge Registers: RegisterHub --> GnArea {}

edge HasHousehold: GnArea --> RegHousehold {}

edge HasResident: RegHousehold --> Resident {}

# ---------- Views (the wire format) ----------

obj ResidentRow {
    has name: str;
    has age: int = 0;
    has needs: list[str] = [];
    has evac_help: bool = False;
    has note: str = "";
}

obj HouseholdRow {
    has hh_id: str;
    has address: str = "";
    has head: str = "";
    has phone: str = "";
    has people: int = 0;
    has residents: list[ResidentRow] = [];
    has vulnerable: list[str] = [];
    has evac_help: bool = False;
    has note: str = "";
    has heard: bool = False;
    has last_heard: str = "";
    has links: list[str] = [];
    has inc_ids: list[str] = [];
    has status: str = "";
    has verified_call: str = "";
    has relief: list[str] = [];
    has possible: list[str] = [];
    has action: str = "";
    has tone: str = "slate";
    has group: int = 0;
}

obj GnRegisterView {
    has gn: str;
    has ds: str = "";
    has district: str = "";
    has officer: str = "";
    has households: int = 0;
    has people: int = 0;
    has vulnerable_households: int = 0;
    has heard: int = 0;
    has check_now: int = 0;
    has rows: list[HouseholdRow] = [];
    has note: str = "";
}

obj GnChoice {
    has gn: str;
    has ds: str = "";
    has district: str = "";
    has officer: str = "";
    has households: int = 0;
    has people: int = 0;
}

# ---------- Seeding (once per version) ----------

def register_paths() -> list[str] {
    paths: list[str] = [os.path.join("ekata", "fixtures", REGISTER_FILE)];
    try {
        paths.append(os.path.join(os.path.dirname(__file__), "fixtures", REGISTER_FILE));
    } except Exception {
        paths.append(os.path.join("fixtures", REGISTER_FILE));
    }
    return paths;
}

def load_register_data() -> list[any] {
    for p in register_paths() {
        if os.path.exists(p) {
            try {
                with open(p, "r", encoding="utf-8") as fh {
                    raw = fh.read();
                }
                data: any = json.loads(raw);
                return list(data.get("areas", []));
            } except Exception {
                continue;
            }
        }
    }
    return [];
}

def find_register() -> RegisterHub | None {
    hubs = [root.shared -->][?:RegisterHub, name == REGISTER_NAME];
    if len(hubs) > 0 {
        return hubs[0];
    }
    return None;
}

def make_register() -> RegisterHub {
    created = root.shared ++> RegisterHub(name=REGISTER_NAME);
    return created;
}

def wipe_register(reg: RegisterHub) {
    for area in [reg ->:Registers:->[?:GnArea]] {
        for hh in [area ->:HasHousehold:->[?:RegHousehold]] {
            for r in [hh ->:HasResident:->[?:Resident]] {
                del r;
            }
            del hh;
        }
        del area;
    }
}

def seed_register(reg: RegisterHub) {
    for a in load_register_data() {
        area = GnArea(
            gn=str(a.get("gn", "")), ds=str(a.get("ds", "")),
            district=str(a.get("district", "")), officer=str(a.get("officer", ""))
        );
        reg +>:Registers:+> area;
        for h in a.get("households", []) {
            phones: list[str] = [];
            for raw in h.get("phones", []) {
                canon = normalise_phone(str(raw));
                if canon != "" and canon not in phones {
                    phones.append(canon);
                }
            }
            hh = RegHousehold(
                hh_id=str(h.get("id", "")), house=str(h.get("house", "")),
                road=str(h.get("road", "")), phones=phones, note=str(h.get("note", ""))
            );
            area +>:HasHousehold:+> hh;
            for r in h.get("residents", []) {
                nm = str(r.get("name", ""));
                res = Resident(
                    name=nm, canonical=normalise_name(nm), age=int(r.get("age", 0)),
                    needs=[str(x) for x in r.get("needs", [])],
                    evac_help=bool(r.get("evac_help", False)), note=str(r.get("note", ""))
                );
                hh +>:HasResident:+> res;
            }
        }
    }
    reg.version = REGISTER_VERSION;
}

# Readers: the seeded register, or None (reads never seed, so they stay pure).
def current_register() -> RegisterHub | None {
    found = find_register();
    if found is not None and found.version == REGISTER_VERSION {
        return found;
    }
    return None;
}

# Writers only, inside their graph_writer block: create and seed once per version.
def ensure_register() -> RegisterHub {
    existing = find_register();
    reg: RegisterHub = existing if existing is not None else make_register();
    if reg.version != REGISTER_VERSION {
        wipe_register(reg);
        seed_register(reg);
    }
    return reg;
}

def register_size(reg: RegisterHub) -> int {
    n = 0;
    for area in [reg ->:Registers:->[?:GnArea]] {
        n += len([area ->:HasHousehold:->[?:RegHousehold]]);
    }
    return n;
}

def find_area(reg: RegisterHub, gn: str) -> GnArea | None {
    for area in [reg ->:Registers:->[?:GnArea]] {
        if area.gn.lower() == gn.strip().lower() {
            return area;
        }
    }
    return None;
}

# ---------- Linking (read-only) ----------

def place_tokens(s: str) -> list[str] {
    return [t for t in normalise_place(s).split() if t != ""];
}

# The words that name a road ("hettimulla" for "Hettimulla Road").
def road_words(road: str) -> list[str] {
    return [t for t in place_tokens(road) if t not in ROAD_WORDS];
}

# A household-level Place names this registered house when it has the same
# house number (or every landmark word) and the same road name.
def place_matches(hh: RegHousehold, place: Place) -> bool {
    if place.level != "HOUSEHOLD" {
        return False;
    }
    parts = place.name.split("|");
    house_part = parts[0].split();
    area_part: list[str] = [];
    if len(parts) > 1 {
        area_part = parts[1].split();
    }
    house_toks = place_tokens(hh.house);
    rw = road_words(hh.road);
    if len(house_toks) == 0 or len(rw) == 0 {
        return False;
    }
    for t in house_toks {
        if t not in house_part {
            return False;
        }
    }
    everywhere = house_part + area_part;
    for w in rw {
        if w not in everywhere {
            return False;
        }
    }
    return True;
}

obj Hit {
    has msg: Message;
    has why: str;
}

obj Links {
    has hits: list[Hit] = [];
    has possible: list[str] = [];
}

def names_in(m: Message) -> list[str] {
    return [pn.canonical for pn in [m ->:Names:->[?:PersonName]]];
}

# STRONG hits make the household "heard"; a house-only match is a lead.
def household_links(hub: EkataHub, hh: RegHousehold, residents: list[Resident], places: list[Place]) -> Links {
    out = Links();
    seen: list[str] = [];
    for canon in hh.phones {
        for ph in [hub ->:Holds:->[?:Phone, number == canon]] {
            for m in [ph <-:HasPhone:<-[?:Message]] {
                if m.kind in LINK_KINDS and m.msg_id not in seen {
                    seen.append(m.msg_id);
                    out.hits.append(Hit(msg=m, why=f"registered phone {phone_display(canon)} in {m.msg_id}"));
                }
            }
        }
    }
    full_names = [r.canonical for r in residents if is_full_name(r.canonical)];
    for pl in places {
        if not place_matches(hh, pl) {
            continue;
        }
        for m in [pl <-:At:<-[?:Message]] {
            if m.kind not in LINK_KINDS or m.msg_id in seen {
                continue;
            }
            seen.append(m.msg_id);
            named = [n for n in names_in(m) if n in full_names];
            if len(named) > 0 {
                out.hits.append(Hit(msg=m, why=f"same house and resident {named[0]} in {m.msg_id}"));
            } else {
                out.possible.append(f"{m.msg_id} gives this house but no registered phone or resident name: check by phone");
            }
        }
    }
    return out;
}

# The newest call that reached the household, ordered in storm time.
def newest_verifying_call(inc: Incident) -> CallLog | None {
    best: CallLog | None = None;
    best_t = -1;
    for c in calls_of(inc) {
        t = storm_minutes(c.storm_time);
        if c.outcome in VERIFIED_OUTCOMES and t >= best_t {
            best = c;
            best_t = t;
        }
    }
    return best;
}

# A resident's full name in a message that is not already linked: a lead for
# the officer, never a link (a name alone is not strong evidence).
def name_leads(residents: list[Resident], linked: list[str], names: list[PersonName]) -> list[str] {
    out: list[str] = [];
    for r in residents {
        if not is_full_name(r.canonical) {
            continue;
        }
        for pn in names {
            if pn.canonical != r.canonical {
                continue;
            }
            for m in [pn <-:Names:<-[?:Message]] {
                if m.kind not in LINK_KINDS {
                    continue;
                }
                for inc in [m ->:PartOf:->[?:Incident]] {
                    tag = f"{r.name} is named in {m.msg_id} ({inc.inc_id}): name only, check by phone";
                    if inc.inc_id not in linked and tag not in out {
                        out.append(tag);
                    }
                }
            }
        }
    }
    return out;
}

# ---------- The officer's view ----------

def address_of(hh: RegHousehold) -> str {
    if hh.house == "" {
        return hh.road;
    }
    if hh.house[0].isdigit() {
        return f"No. {hh.house}, {hh.road}";
    }
    return f"{hh.house}, {hh.road}";
}

def household_row(hub: EkataHub, hh: RegHousehold, places: list[Place], names: list[PersonName]) -> HouseholdRow {
    residents = [hh ->:HasResident:->[?:Resident]];
    flags: list[str] = [];
    for r in residents {
        for n in r.needs {
            if n not in flags {
                flags.append(n);
            }
        }
    }
    evac = len([r for r in residents if r.evac_help]) > 0;
    found = household_links(hub, hh, residents, places);
    hits = found.hits;
    incs: list[Incident] = [];
    inc_ids: list[str] = [];
    last = "";
    for h in hits {
        if last == "" or storm_minutes(h.msg.storm_time) > storm_minutes(last) {
            last = h.msg.storm_time;
        }
        for inc in [h.msg ->:PartOf:->[?:Incident]] {
            if inc.inc_id not in inc_ids {
                inc_ids.append(inc.inc_id);
                incs.append(inc);
            }
        }
    }
    status = "";
    verified = "";
    relief: list[str] = [];
    resolved = False;
    for inc in incs {
        if status == "" {
            status = inc.status;
        }
        if inc.status == "RESOLVED" {
            resolved = True;
        }
        c = newest_verifying_call(inc);
        if c is not None {
            verified = f"{c.outcome} by {c.desk} at {c.storm_time}";
        }
        for req in requests_of(inc) {
            relief.append(f"{req.need}: {req.status}" + (f" ({req.ngo})" if req.ngo != "" else ""));
        }
    }
    heard = len(hits) > 0;
    vulnerable = len(flags) > 0 or evac;
    action = "In the call queue, not yet verified by phone";
    tone = "orange";
    group = 1;
    if not heard and vulnerable {
        action = "Check on them now: vulnerable and not heard from tonight";
        tone = "red";
        group = 0;
    } elif not heard {
        action = "Not heard from tonight";
        tone = "amber";
        group = 2;
    } elif resolved {
        action = "Resolved tonight";
        tone = "green";
        group = 4;
    } elif verified != "" {
        action = "Verified by phone";
        tone = "blue";
        group = 3;
    }
    return HouseholdRow(
        hh_id=hh.hh_id, address=address_of(hh),
        head=residents[0].name if len(residents) > 0 else "",
        phone=phone_display(hh.phones[0]) if len(hh.phones) > 0 else "",
        people=len(residents),
        residents=[
            ResidentRow(name=r.name, age=r.age, needs=r.needs, evac_help=r.evac_help, note=r.note)
            for r in residents
        ],
        vulnerable=flags, evac_help=evac, note=hh.note, heard=heard, last_heard=last,
        links=[h.why for h in hits][:4], inc_ids=inc_ids, status=status, verified_call=verified,
        relief=relief, possible=(found.possible + name_leads(residents, inc_ids, names))[:3],
        action=action, tone=tone, group=group
    );
}

def gn_register_in(hub: EkataHub, reg: RegisterHub | None, gn: str) -> GnRegisterView {
    if reg is None {
        return GnRegisterView(gn=gn, note="The register is not set up yet.");
    }
    area = find_area(reg, gn);
    if area is None {
        return GnRegisterView(gn=gn, note="No register for this GN division yet.");
    }
    places = [hub ->:Holds:->[?:Place, level == "HOUSEHOLD"]];
    names = [hub ->:Holds:->[?:PersonName]];
    rows = [household_row(hub, hh, places, names) for hh in [area ->:HasHousehold:->[?:RegHousehold]]];
    rows = sorted(rows, key=lambda (r: HouseholdRow) { (r.group, -len(r.vulnerable), r.hh_id); });
    return GnRegisterView(
        gn=area.gn, ds=area.ds, district=area.district, officer=area.officer,
        households=len(rows), people=sum([r.people for r in rows]),
        vulnerable_households=len([r for r in rows if len(r.vulnerable) > 0 or r.evac_help]),
        heard=len([r for r in rows if r.heard]),
        check_now=len([r for r in rows if r.group == 0]),
        rows=rows,
        note="Synthetic register. Linked only by a registered phone or the same house on the same road; a surname or road alone never links."
    );
}

# Audit: one Decision each time an officer opens a GN's register (never on a poll).
def log_register_open(hub: EkataHub, reg: RegisterHub, gn: str, officer: str) -> bool {
    area = find_area(reg, gn);
    if area is None {
        return False;
    }
    who = officer.strip() if officer.strip() != "" else area.officer;
    log_decision(
        hub, "officer", "open_register",
        f"{who} opened the household register for {area.gn} (read only; personal data, flood response use)",
        "APPLIED", hub.storm_time, [], confidence=1.0, model="human", target_label=area.gn
    );
    return True;
}

def gn_choices_in(reg: RegisterHub | None) -> list[GnChoice] {
    out: list[GnChoice] = [];
    if reg is None {
        return out;
    }
    for area in [reg ->:Registers:->[?:GnArea]] {
        hhs = [area ->:HasHousehold:->[?:RegHousehold]];
        people = 0;
        for hh in hhs {
            people += len([hh ->:HasResident:->[?:Resident]]);
        }
        out.append(GnChoice(
            gn=area.gn, ds=area.ds, district=area.district, officer=area.officer,
            households=len(hhs), people=people
        ));
    }
    return sorted(out, key=lambda (c: GnChoice) { (c.district, c.ds, c.gn); });
}
