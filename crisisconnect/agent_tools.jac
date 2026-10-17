"""CrisisConnect agent tools: read-only lookups an LLM agent may call (rule R14: tools never write).

Every tool takes strings and returns one compact string that cites ids.
Each tool has a *_in(hub, ...) twin so tests can run it on a private hub.
"""

import from crisisconnect.schema {
    CrisisConnectHub, Holds, Message, Incident, CallLog, Logged, Names, PersonName, PartOf,
    GNDivision, DSDivision, District, InDS, InDistrict, LocatedIn, Appeal, PaysTo,
    AppealHasPhone, Links, BankAccount, Phone, Url, RegistryEntry, Bulletin
}
import from crisisconnect.store {
    get_hub, find_incident, messages_of, has_call_log, storm_diff, fmt_minutes,
    normalise_phone, normalise_name, normalise_place, place_compatible, all_incidents
}
import from crisisconnect.referee { OPEN_STATUSES }

glob FLAG_WORDS: dict[str, list[str]] = {
    "elderly": ["elderly", "wheelchair", "grand", "old"],
    "child": ["child", "baby", "kid", "daughter", "son"],
    "medical": ["medical", "insulin", "asthma", "dialysis", "fever", "injured"],
    "disability": ["disability", "disabled", "blind", "deaf"],
    "pregnant": ["pregnant"]
};

def clip(s: str, n: int = 600) -> str {
    if len(s) <= n {
        return s;
    }
    return s[0:n - 3] + "...";
}

def not_found(inc_id: str) -> str {
    return f"not found: no incident {inc_id}";
}

def join_or(items: list[str], empty: str) -> str {
    if len(items) == 0 {
        return empty;
    }
    return ", ".join(items);
}

def outcomes_of(inc: Incident) -> list[str] {
    out: list[str] = [];
    for c in [inc <-:Logged:<-[?:CallLog]] {
        out.append(f"{c.outcome} by {c.desk} {c.storm_time}");
    }
    return out;
}

def gn_of(inc: Incident) -> GNDivision | None {
    gns = [inc ->:LocatedIn:->[?:GNDivision]];
    if len(gns) > 0 {
        return gns[0];
    }
    return None;
}

# 1
def incident_summary_in(hub: CrisisConnectHub, inc_id: str) -> str {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return not_found(inc_id);
    }
    gn = gn_of(inc);
    area = inc.gn;
    if gn is not None {
        area = gn.name;
        for ds in [gn ->:InDS:->[?:DSDivision]] {
            area = f"{gn.name} / DS {ds.name}";
        }
    }
    n = len(messages_of(inc));
    place = inc.place if inc.place != "" else "unknown";
    owner = inc.claimed_by if inc.claimed_by != "" else "nobody";
    where = area if area != "" else "not linked";
    s = f"{inc.inc_id} {inc.status}, {inc.headcount} people, needs: {join_or(inc.needs, 'none')}; vulnerable: {join_or(inc.vulnerable, 'none')}; place: {place}; GN/DS: {where}; {n} messages; last update {inc.last_seen}; claimed_by: {owner}";
    return clip(s);
}

"""Summarise one incident by id (status, headcount, needs, vulnerable, place, GN/DS, messages, owner)."""
def incident_summary(inc_id: str) -> str {
    return incident_summary_in(get_hub(), inc_id);
}

# 2
def incident_timeline_in(hub: CrisisConnectHub, inc_id: str) -> str {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return not_found(inc_id);
    }
    ms = messages_of(inc);
    if len(ms) == 0 {
        return f"{inc.inc_id}: no messages";
    }
    lines: list[str] = [];
    for m in ms[0:10] {
        lines.append(f"[{m.msg_id} {m.storm_time} {m.channel}] {m.text[0:90]}");
    }
    return clip(f"{inc.inc_id} timeline ({len(ms)} msgs): " + " | ".join(lines), 1200);
}

"""List an incident's messages in order (id, storm time, channel, first 90 chars), at most 10."""
def incident_timeline(inc_id: str) -> str {
    return incident_timeline_in(get_hub(), inc_id);
}

# 3
def vulnerable_flags_in(hub: CrisisConnectHub, inc_id: str) -> str {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return not_found(inc_id);
    }
    if len(inc.vulnerable) == 0 {
        return f"{inc.inc_id}: no vulnerable flags";
    }
    ms = messages_of(inc);
    parts: list[str] = [];
    for flag in inc.vulnerable {
        words = [flag.lower()];
        for k in FLAG_WORDS.keys() {
            if flag.lower() == k or flag.lower() in FLAG_WORDS[k] {
                words = FLAG_WORDS[k];
            }
        }
        ids: list[str] = [];
        for m in ms {
            low = m.text.lower();
            for w in words {
                if w in low {
                    ids.append(m.msg_id);
                    break;
                }
            }
        }
        parts.append(f"{flag} <- {join_or(ids, 'no message cites it')}");
    }
    return clip(f"{inc.inc_id} flags: " + "; ".join(parts));
}

"""Show an incident's vulnerable flags and the message ids whose text mentions each."""
def vulnerable_flags(inc_id: str) -> str {
    return vulnerable_flags_in(get_hub(), inc_id);
}

# 4
def waiting_time_in(hub: CrisisConnectHub, inc_id: str) -> str {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return not_found(inc_id);
    }
    w = storm_diff(hub.storm_time, inc.first_seen);
    return f"{inc.inc_id} ({inc.status}) waiting {fmt_minutes(w)}: first seen {inc.first_seen}, storm time now {hub.storm_time}";
}

"""Storm-time minutes an incident has waited since first seen."""
def waiting_time(inc_id: str) -> str {
    return waiting_time_in(get_hub(), inc_id);
}

# 5
def verified_incident_for_in(hub: CrisisConnectHub, place: str, names: str) -> str {
    pl = normalise_place(place);
    wanted: list[str] = [];
    for raw in names.split(",") {
        n = normalise_name(raw);
        if n != "" {
            wanted.append(n);
        }
    }
    hits: list[str] = [];
    for inc in all_incidents(hub) {
        if inc.status != "CONFIRMED" {
            continue;
        }
        why: list[str] = [];
        if pl != "" and place_compatible(pl, normalise_place(inc.place)) {
            why.append("place");
        }
        for m in messages_of(inc) {
            for pn in [m ->:Names:->[?:PersonName]] {
                for w in wanted {
                    if pn.canonical != "" and (w in pn.canonical or pn.canonical in w) {
                        tag = f"name {pn.canonical} in {m.msg_id}";
                        if tag not in why {
                            why.append(tag);
                        }
                    }
                }
            }
        }
        if len(why) > 0 {
            hits.append(f"{inc.inc_id} CONFIRMED at {inc.place} ({'; '.join(why)}); calls: {join_or(outcomes_of(inc), 'no call log')}");
        }
    }
    if len(hits) == 0 {
        return "not found: no CONFIRMED incident matches that place or name";
    }
    return clip(" | ".join(hits));
}

"""Find CONFIRMED incidents matching a place and/or comma-separated names, with call log outcomes."""
def verified_incident_for(place: str, names: str) -> str {
    return verified_incident_for_in(get_hub(), place, names);
}

# 6 and 7
def registry_match(hub: CrisisConnectHub, query: str, kind: str) -> list[RegistryEntry] {
    q = query.strip().lower();
    out: list[RegistryEntry] = [];
    if q == "" {
        return out;
    }
    for r in [hub ->:Holds:->[?:RegistryEntry]] {
        o = r.office.lower();
        if r.kind == kind and (q in o or o in q) {
            out.append(r);
        }
    }
    return out;
}

def lookup_official_in(hub: CrisisConnectHub, name: str, office: str) -> str {
    hits = registry_match(hub, office, "OFFICE");
    if len(hits) == 0 {
        return f"not in registry: no official office matches '{office}' (asked about {name})";
    }
    parts = [f"{r.office}, contact {r.contact}" for r in hits];
    return clip("registry OFFICE: " + " | ".join(parts));
}

"""Check a claimed official's office against the registry and return the registered contact."""
def lookup_official(name: str, office: str) -> str {
    return lookup_official_in(get_hub(), name, office);
}

def lookup_ngo_in(hub: CrisisConnectHub, name: str) -> str {
    hits = registry_match(hub, name, "NGO");
    if len(hits) == 0 {
        return f"not in registry: no NGO matches '{name}'";
    }
    parts = [f"{r.office}, contact {r.contact}" for r in hits];
    return clip("registry NGO: " + " | ".join(parts));
}

"""Check an organisation name against the registry of NGOs and return its registered contact."""
def lookup_ngo(name: str) -> str {
    return lookup_ngo_in(get_hub(), name);
}

# 8
def appeals_sharing_in(hub: CrisisConnectHub, identifier: str) -> str {
    ident = identifier.strip();
    if ident == "" {
        return "not found: empty identifier";
    }
    canon = normalise_phone(ident);
    ids: list[str] = [];
    how: list[str] = [];
    for acct in [hub ->:Holds:->[?:BankAccount]] {
        if acct.account.lower() == ident.lower() {
            how.append("account");
            for ap in [acct <-:PaysTo:<-[?:Appeal]] {
                if ap.appeal_id not in ids {
                    ids.append(ap.appeal_id);
                }
            }
        }
    }
    if canon != "" {
        for ph in [hub ->:Holds:->[?:Phone]] {
            if ph.number == canon {
                how.append("phone");
                for ap in [ph <-:AppealHasPhone:<-[?:Appeal]] {
                    if ap.appeal_id not in ids {
                        ids.append(ap.appeal_id);
                    }
                }
            }
        }
    }
    for u in [hub ->:Holds:->[?:Url]] {
        if u.value.lower() == ident.lower() {
            how.append("url");
            for ap in [u <-:Links:<-[?:Appeal]] {
                if ap.appeal_id not in ids {
                    ids.append(ap.appeal_id);
                }
            }
        }
    }
    if len(ids) == 0 {
        return f"not found: no appeal uses {ident}";
    }
    return clip(f"{len(ids)} appeals share {ident} ({join_or(how, '')}): {', '.join(ids)}");
}

"""List appeals that use the same payee account, phone number or URL, with a count."""
def appeals_sharing(identifier: str) -> str {
    return appeals_sharing_in(get_hub(), identifier);
}

# 9
def official_channel_for_in(hub: CrisisConnectHub, gn_division: str) -> str {
    q = gn_division.strip().lower();
    allgn = [hub ->:Holds:->[?:GNDivision]];
    gns = [g for g in allgn if q != "" and g.name.lower() == q];
    if len(gns) == 0 {
        gns = [g for g in allgn if q != "" and (q in g.name.lower() or g.name.lower() in q)];
    }
    if len(gns) == 0 {
        return f"not found: no GN division '{gn_division}'";
    }
    gn = gns[0];
    dsn = "";
    dist = "";
    for ds in [gn ->:InDS:->[?:DSDivision]] {
        dsn = ds.name;
        for d in [ds ->:InDistrict:->[?:District]] {
            dist = d.name;
        }
    }
    offices: list[str] = [];
    for r in [hub ->:Holds:->[?:RegistryEntry]] {
        if r.kind == "OFFICE" and dist != "" and dist.lower() in r.office.lower() {
            offices.append(f"{r.office} {r.contact}");
        }
    }
    return clip(
        f"{gn.name}: DS {dsn}, district {dist}. Offices: {join_or(offices, 'none registered')}. Aid data is collected through the Divisional Secretariat and GN officer."
    );
}

"""Give the DS division, district and registered offices for a GN division (the official aid channel)."""
def official_channel_for(gn_division: str) -> str {
    return official_channel_for_in(get_hub(), gn_division);
}

# 10
def official_bulletins_in(hub: CrisisConnectHub, area: str) -> str {
    q = area.strip().lower();
    if q == "" {
        return "not found: empty area";
    }
    lines: list[str] = [];
    for b in [hub ->:Holds:->[?:Bulletin]] {
        a = b.area.lower();
        if q in a or a in q {
            lines.append(f"{b.issuer} {b.issued_at}: {b.text[0:160]}");
        }
    }
    if len(lines) == 0 {
        return f"not found: no bulletin for {area}";
    }
    return clip(" | ".join(lines), 900);
}

"""Return seeded official bulletins (issuer, time, text) whose area matches."""
def official_bulletins(area: str) -> str {
    return official_bulletins_in(get_hub(), area);
}

# 11
def open_incidents_in_in(hub: CrisisConnectHub, gn_division: str) -> str {
    q = gn_division.strip().lower();
    if q == "" {
        return "not found: empty GN division";
    }
    lines: list[str] = [];
    for inc in all_incidents(hub) {
        if inc.status not in OPEN_STATUSES {
            continue;
        }
        linked = False;
        gn = gn_of(inc);
        if gn is not None and gn.name.lower() == q {
            linked = True;
        }
        if q in inc.gn.lower() or q in inc.place.lower() {
            linked = True;
        }
        if linked {
            lines.append(f"{inc.inc_id} {inc.status} {inc.headcount} people, needs: {join_or(inc.needs, 'none')}");
        }
    }
    if len(lines) == 0 {
        return f"not found: no open incidents in {gn_division}";
    }
    return clip(f"{len(lines)} open in {gn_division}: " + " | ".join(lines));
}

"""List open incidents in a GN division with their needs."""
def open_incidents_in(gn_division: str) -> str {
    return open_incidents_in_in(get_hub(), gn_division);
}

glob AGENT_TOOLS: list[any] = [
    incident_summary, incident_timeline, vulnerable_flags, waiting_time,
    verified_incident_for, lookup_official, lookup_ngo, appeals_sharing,
    official_channel_for, official_bulletins, open_incidents_in
];
