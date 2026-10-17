"""Role portals: what each kind of person sees, and the agents that connect them.

  Citizen  sends an SOS or a message to check, tracks it, reads bulletins.
  Officer  (Grama Niladhari / divisional desk) works one DS division's queue,
           pins the GN division, asks an NGO for a resource.
  NGO      receives matched resource requests, accepts, declines, delivers.
  District sees every division, escalations, bulletins and the agent log.

The resource matcher is an agent: it scores registered NGOs by area and what
they offer, lets the model pick among the top candidates when AI is on, and
falls back to the next NGO when one declines.
"""

import from crisisconnect.instrumentation { NativeSpan }
import os;
import from crisisconnect.schema {
    CrisisConnectHub, Holds, Incident, Message, GNDivision, DSDivision, District, InDS, InDistrict,
    LocatedIn, RegistryEntry, Bulletin, Appeal, RumourClaim, CallLog, Logged,
    ResourceRequest, RequestFor, SentTo
}
import from crisisconnect.views { QueueRow }
import from crisisconnect.store {
    all_incidents, find_incident, find_message, incident_of, messages_of, log_decision,
    storm_diff, fmt_minutes, has_call_log
}
import from crisisconnect.referee { OPEN_STATUSES }
import from crisisconnect.coordinator { build_queue }
import from crisisconnect.ai.models { fast, last_model }

# ---------- Views ----------

obj DivisionView {
    has ds: str;
    has district: str;
    has officer: str;
    has gns: list[str] = [];
    has open_count: int = 0;
    has vulnerable_open: int = 0;
    has unanswered: int = 0;
}

obj RequestView {
    has req_id: str;
    has inc_id: str;
    has need: str;
    has status: str;
    has ngo: str = "";
    has ngo_contact: str = "";
    has reason: str = "";
    has requested_by: str = "";
    has storm_time: str = "";
    has place: str = "";
    has headcount: int = 0;
    has vulnerable: list[str] = [];
    has declined_by: list[str] = [];
}

obj NgoView {
    has office: str;
    has contact: str;
    has kind: str;
    has areas: list[str] = [];
    has offers: list[str] = [];
    has open_requests: int = 0;
}

obj BulletinView {
    has issuer: str;
    has area: str;
    has text: str;
    has issued_at: str = "";
}

obj CitizenStatus {
    has msg_id: str;
    has found: bool = False;
    has kind: str = "";
    has stage: int = 0;
    has stage_label: str = "";
    has detail: str = "";
    has inc_id: str = "";
    has ds: str = "";
    has gn: str = "";
    has officer: str = "";
    has help: list[str] = [];
    has verdict: str = "";
    has verdict_reason: str = "";
}

obj EscalationRow {
    has inc_id: str;
    has place: str;
    has ds: str;
    has waiting_min: int;
    has waiting: str;
    has level: str;
    has reason: str;
    has headcount: int = 0;
    has vulnerable: list[str] = [];
}

obj DistrictOverview {
    has storm_time: str = "";
    has messages: int = 0;
    has open_incidents: int = 0;
    has unanswered: int = 0;
    has vulnerable_open: int = 0;
    has open_requests: int = 0;
    has uncovered_requests: int = 0;
    has divisions: list[DivisionView] = [];
    has escalations: list[EscalationRow] = [];
}

# ---------- NGO profiles (synthetic: areas served and what they offer) ----------

glob NGO_PROFILES: dict[str, dict[str, list[str]]] = {
    "Kegalle Volunteer Kitchen": {"areas": ["Kegalle", "Mawanella", "Rambukkana", "Warakapola"], "offers": ["food", "water", "shelter"]},
    "Hill Country Relief Trust": {"areas": ["Mawanella", "Aranayaka", "Aranayake", "Yatiyantota", "Dehiowita"], "offers": ["boat", "medicine", "food", "transport"]},
    "Hill Country Aid Circle": {"areas": ["Kegalle", "Aranayaka"], "offers": ["medicine", "food"]},
    "Kelani Valley Volunteers": {"areas": ["Yatiyantota", "Dehiowita", "Kegalle"], "offers": ["boat", "transport", "food"]},
    "Green Ridge Boat Volunteers": {"areas": ["Mawanella", "Kegalle", "Rambukkana", "Ratnapura"], "offers": ["boat", "transport"]},
    "Ratnapura Helping Hands Society": {"areas": ["Ratnapura", "Kuruwita", "Eheliyagoda", "Pelmadulla", "Balangoda"], "offers": ["food", "shelter", "medicine", "boat"]}
};

glob NEED_WORDS: dict[str, list[str]] = {
    "boat": ["boat", "rescue", "evacuat", "trapped", "roof"],
    "medicine": ["medic", "insulin", "doctor", "injur", "sick", "pregnan"],
    "food": ["food", "meal", "hungry", "dry ration"],
    "water": ["water", "drink"],
    "shelter": ["shelter", "camp", "place to stay"],
    "transport": ["transport", "vehicle", "lorry", "tractor"]
};

glob RESOURCE_KINDS: list[str] = ["boat", "medicine", "food", "water", "shelter", "transport"];

def ngo_profile(office: str) -> dict[str, list[str]] {
    if office in NGO_PROFILES {
        return NGO_PROFILES[office];
    }
    return {"areas": [], "offers": ["food"]};
}

def normal_need(need: str) -> str {
    low = need.lower().strip();
    for (kind, words) in NEED_WORDS.items() {
        if low == kind {
            return kind;
        }
        for w in words {
            if w in low {
                return kind;
            }
        }
    }
    return low if low != "" else "food";
}

# ---------- Spine helpers ----------

def ds_of(inc: Incident) -> DSDivision | None {
    for gn in [inc ->:LocatedIn:->[?:GNDivision]] {
        for ds in [gn ->:InDS:->[?:DSDivision]] {
            return ds;
        }
    }
    return None;
}

def district_of(ds: DSDivision) -> str {
    for d in [ds ->:InDistrict:->[?:District]] {
        return d.name;
    }
    return "";
}

def find_ds(hub: CrisisConnectHub, name: str) -> DSDivision | None {
    for ds in [hub ->:Holds:->[?:DSDivision]] {
        if ds.name.lower() == name.lower() {
            return ds;
        }
    }
    return None;
}

def officer_for(ds_name: str) -> str {
    return f"Divisional desk, {ds_name}";
}

glob VERIFIED_OUTCOMES: list[str] = ["REACHED_CONFIRMED", "STILL_IN_NEED", "RESCUED"];

def calls_of(inc: Incident) -> list[CallLog] {
    return [inc <-:Logged:<-[?:CallLog]];
}

# The newest call that actually reached the household (no-answer calls never verify).
def verifying_call(inc: Incident) -> CallLog | None {
    best: CallLog | None = None;
    for c in calls_of(inc) {
        if c.outcome in VERIFIED_OUTCOMES and (best is None or c.storm_time >= best.storm_time) {
            best = c;
        }
    }
    return best;
}

def is_verified(inc: Incident) -> bool {
    return verifying_call(inc) is not None;
}

def no_answer_count(inc: Incident) -> int {
    return len([c for c in calls_of(inc) if c.outcome == "NO_ANSWER"]);
}

def is_open(inc: Incident) -> bool {
    return inc.status in OPEN_STATUSES;
}

# ---------- Divisions (officer entry and district overview) ----------

def division_views(hub: CrisisConnectHub) -> list[DivisionView] {
    rows: list[DivisionView] = [];
    for ds in [hub ->:Holds:->[?:DSDivision]] {
        gns = [g.name for g in [ds <-:InDS:<-[?:GNDivision]]];
        rows.append(DivisionView(ds=ds.name, district=district_of(ds), officer=officer_for(ds.name), gns=gns));
    }
    by_name: dict[str, DivisionView] = {};
    for r in rows {
        by_name[r.ds] = r;
    }
    for inc in all_incidents(hub) {
        if not is_open(inc) {
            continue;
        }
        ds = ds_of(inc);
        if ds is None or ds.name not in by_name {
            continue;
        }
        v = by_name[ds.name];
        v.open_count += 1;
        if len(inc.vulnerable) > 0 {
            v.vulnerable_open += 1;
        }
        if not is_verified(inc) {
            v.unanswered += 1;
        }
    }
    return sorted(rows, key=lambda (r: DivisionView) { (-r.open_count, r.district, r.ds); });
}

def officer_rows(hub: CrisisConnectHub, ds_name: str) -> list[QueueRow] {
    keep: list[str] = [];
    for inc in all_incidents(hub) {
        ds = ds_of(inc);
        if ds is not None and ds.name.lower() == ds_name.lower() {
            keep.append(inc.inc_id);
        }
    }
    rows = [r for r in build_queue(hub) if r.inc_id in keep];
    for (i, r) in enumerate(rows) {
        r.rank = i + 1;
    }
    return rows;
}

# Officer pins the exact GN division (the router only knows the DS division).
def pin_gn(hub: CrisisConnectHub, inc_id: str, gn_name: str, officer: str) -> bool {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return False;
    }
    target: GNDivision | None = None;
    for g in [hub ->:Holds:->[?:GNDivision]] {
        if g.name.lower() == gn_name.lower() {
            target = g;
        }
    }
    if target is None {
        return False;
    }
    for old in [inc ->:LocatedIn:->[?:GNDivision]] {
        inc del --> old;
    }
    inc +>:LocatedIn:+> target;
    inc.gn = target.name;
    log_decision(
        hub, "officer", "pin_gn", f"{officer} placed {inc_id} in {target.name}", "APPLIED",
        hub.storm_time, [inc], confidence=1.0, model="human", target_label=inc_id
    );
    return True;
}

# ---------- Resource matcher agent ----------

obj NgoCandidate {
    has office: str;
    has areas: list[str];
    has offers: list[str];
    has open_requests: int;
    has score: float;
}

obj NgoPick {
    has office: str;
    has reason: str;
}

sem NgoCandidate.score = "Rules score: 2 for serving the incident's division, 1 for its district, plus 2 if it offers the need; minus 0.5 per request it already holds.";
sem NgoPick.office = "Exactly one office name copied from the candidates list.";
sem NgoPick.reason = "One plain sentence a volunteer would understand: why this group, for this need, in this place.";

def choose_ngo(need: str, place: str, division: str, vulnerable: list[str], candidates: list[NgoCandidate]) -> NgoPick by fast(
    temperature=0.0,
    incl_info={"policy": "Pick the registered group most able to deliver this need to this place tonight. Prefer groups serving the division, offering the need, and with fewer open requests. People with vulnerable flags need the most reliable group. Never invent a group."}
);

def open_count_for(hub: CrisisConnectHub, office: str) -> int {
    n = 0;
    for r in [hub ->:Holds:->[?:ResourceRequest]] {
        if r.ngo == office and r.status in ["REQUESTED", "ACCEPTED", "DISPATCHED"] {
            n += 1;
        }
    }
    return n;
}

def rank_candidates(hub: CrisisConnectHub, need: str, division: str, district: str, exclude: list[str]) -> list[NgoCandidate] {
    out: list[NgoCandidate] = [];
    for reg in [hub ->:Holds:->[?:RegistryEntry]] {
        if reg.kind != "NGO" or reg.office in exclude {
            continue;
        }
        prof = ngo_profile(reg.office);
        areas = prof["areas"];
        offers = prof["offers"];
        # Eligibility first: a group must offer the need and serve the area.
        serves = (division != "" and division in areas) or (district != "" and district in areas);
        if need not in offers or not serves {
            continue;
        }
        score = 0.0;
        if division != "" and division in areas {
            score += 2.0;
        } elif district != "" and district in areas {
            score += 1.0;
        }
        if need in offers {
            score += 2.0;
        }
        held = open_count_for(hub, reg.office);
        score -= 0.5 * held;
        out.append(NgoCandidate(office=reg.office, areas=areas, offers=offers, open_requests=held, score=score));
    }
    return sorted(out, key=lambda (c: NgoCandidate) { (-c.score, c.office); });
}

def registry_entry(hub: CrisisConnectHub, office: str) -> RegistryEntry | None {
    for reg in [hub ->:Holds:->[?:RegistryEntry]] {
        if reg.office == office {
            return reg;
        }
    }
    return None;
}

# Route a request to the best NGO not yet tried. Returns False when none is left.
def route_request(hub: CrisisConnectHub, req: ResourceRequest, inc: Incident) -> bool {
    ds = ds_of(inc);
    division = ds.name if ds is not None else "";
    district = district_of(ds) if ds is not None else "";
    cands = rank_candidates(hub, req.need, division, district, req.declined_by);
    if len(cands) == 0 {
        req.status = "UNCOVERED";
        req.ngo = "";
        tried = len(req.declined_by);
        where = division or district or "this area";
        req.reason = (
            f"Every eligible group for {req.need} in {where} has declined. The district desk must find cover."
            if tried > 0
            else f"No registered group offers {req.need} in {where}. Sent to the district desk."
        );
        log_decision(hub, "matcher", "no_cover", req.reason, "NEEDS_HUMAN", hub.storm_time, [inc], target_label=req.req_id);
        return False;
    }
    top = cands[:3];
    best = top[0];
    reason = f"{best.office} serves {division or district or 'the area'} and offers {req.need}; {len(cands)} eligible group(s)";
    model = "rules";
    if os.environ.get("CRISISCONNECT_AI", "on").lower() != "off" and len(top) > 1 {
        try {
            pick = choose_ngo(req.need, inc.place, division, inc.vulnerable, top);
            names = [c.office for c in top];
            if pick.office in names {
                best = top[names.index(pick.office)];
                reason = pick.reason;
                model = last_model() or "llm";
            }
        } except Exception {
            model = "rules";
        }
    }
    for old in [req ->:SentTo:->] {
        req del --> old;
    }
    reg = registry_entry(hub, best.office);
    if reg is not None {
        req +>:SentTo:+> reg;
    }
    req.ngo = best.office;
    req.status = "REQUESTED";
    req.reason = reason;
    log_decision(
        hub, "matcher", "route_request", reason, "APPLIED", hub.storm_time, [inc],
        confidence=0.8, model=model, target_label=req.req_id
    );
    return True;
}

def next_request_id(hub: CrisisConnectHub) -> str {
    n = len([hub ->:Holds:->[?:ResourceRequest]]) + 1;
    return f"REQ-{n:03d}";
}

def create_request(hub: CrisisConnectHub, inc_id: str, need: str, officer: str) -> ResourceRequest | None {
    with NativeSpan(name="create_request", kind="workflow") {
        inc = find_incident(hub, inc_id);
        if inc is None {
            return None;
        }
        kind = normal_need(need);
        for r in requests_of(inc) {
            if r.need == kind and r.status in ["REQUESTED", "ACCEPTED", "DISPATCHED"] {
                log_decision(
                    hub, "matcher", "duplicate_blocked",
                    f"{inc_id} already has {kind} {r.status.lower()} with {r.ngo or 'the district desk'} ({r.req_id}); no second request sent",
                    "BLOCKED", hub.storm_time, [inc], confidence=1.0, model="rules", target_label=r.req_id
                );
                return r;
            }
        }
        delivered = [r for r in requests_of(inc) if r.need == kind and r.status == "DELIVERED"];
        req = ResourceRequest(req_id=next_request_id(hub), need=kind, requested_by=officer, storm_time=hub.storm_time);
        hub +>:Holds:+> req;
        req +>:RequestFor:+> inc;
        if len(delivered) > 0 {
            log_decision(
                hub, "matcher", "repeat_flagged",
                f"{kind} was already delivered to {inc_id} by {delivered[0].ngo}; a second delivery needs a person to confirm",
                "NEEDS_HUMAN", hub.storm_time, [inc], confidence=1.0, model="rules", target_label=req.req_id
            );
        }
        route_request(hub, req, inc);
        return req;
    }
}

def requests_of(inc: Incident) -> list[ResourceRequest] {
    return [inc <-:RequestFor:<-[?:ResourceRequest]];
}

def incident_of_request(req: ResourceRequest) -> Incident | None {
    for inc in [req ->:RequestFor:->[?:Incident]] {
        return inc;
    }
    return None;
}

def find_request(hub: CrisisConnectHub, req_id: str) -> ResourceRequest | None {
    for r in [hub ->:Holds:->[?:ResourceRequest]] {
        if r.req_id == req_id {
            return r;
        }
    }
    return None;
}

def request_view(hub: CrisisConnectHub, req: ResourceRequest) -> RequestView {
    inc = incident_of_request(req);
    reg = registry_entry(hub, req.ngo) if req.ngo != "" else None;
    return RequestView(
        req_id=req.req_id, inc_id=inc.inc_id if inc is not None else "", need=req.need, status=req.status,
        ngo=req.ngo, ngo_contact=reg.contact if reg is not None else "", reason=req.reason,
        requested_by=req.requested_by, storm_time=req.storm_time,
        place=inc.place if inc is not None else "", headcount=inc.headcount if inc is not None else 0,
        vulnerable=inc.vulnerable if inc is not None else [], declined_by=req.declined_by
    );
}

# NGO answers: accept, decline (re-routes to the next group), dispatched, delivered.
def answer_request(hub: CrisisConnectHub, req_id: str, ngo: str, action: str) -> ResourceRequest | None {
    with NativeSpan(name="answer_request", kind="human") {
        req = find_request(hub, req_id);
        if req is None or req.ngo != ngo {
            return None;
        }
        inc = incident_of_request(req);
        act = action.lower();
        if act == "decline" {
            req.declined_by = req.declined_by + [ngo];
            log_decision(hub, "ngo", "decline", f"{ngo} declined {req.need}", "APPLIED", hub.storm_time, [inc] if inc is not None else [], model="human", target_label=req_id);
            if inc is not None {
                route_request(hub, req, inc);
            }
            return req;
        }
        status_for = {"accept": "ACCEPTED", "dispatched": "DISPATCHED", "delivered": "DELIVERED"};
        if act not in status_for {
            return req;
        }
        req.status = status_for[act];
        log_decision(hub, "ngo", act, f"{ngo} marked {req.need} {req.status.lower()}", "APPLIED", hub.storm_time, [inc] if inc is not None else [], model="human", target_label=req_id);
        return req;
    }
}

def ngo_views(hub: CrisisConnectHub, kind: str) -> list[NgoView] {
    out: list[NgoView] = [];
    for reg in [hub ->:Holds:->[?:RegistryEntry]] {
        if kind != "" and reg.kind != kind {
            continue;
        }
        prof = ngo_profile(reg.office) if reg.kind == "NGO" else {"areas": [], "offers": []};
        out.append(NgoView(office=reg.office, contact=reg.contact, kind=reg.kind, areas=prof["areas"], offers=prof["offers"], open_requests=open_count_for(hub, reg.office)));
    }
    return sorted(out, key=lambda (n: NgoView) { (n.kind, n.office); });
}

def requests_for_ngo(hub: CrisisConnectHub, ngo: str) -> list[RequestView] {
    rows = [request_view(hub, r) for r in [hub ->:Holds:->[?:ResourceRequest]] if r.ngo == ngo or ngo in r.declined_by];
    order = {"REQUESTED": 0, "ACCEPTED": 1, "DISPATCHED": 2, "DELIVERED": 3, "UNCOVERED": 4};
    return sorted(rows, key=lambda (r: RequestView) { (order.get(r.status, 5) if r.ngo == ngo else 6, r.req_id); });
}

def all_request_views(hub: CrisisConnectHub) -> list[RequestView] {
    return [request_view(hub, r) for r in [hub ->:Holds:->[?:ResourceRequest]]];
}

# ---------- Citizen ----------

def bulletin_views(hub: CrisisConnectHub, area: str) -> list[BulletinView] {
    out: list[BulletinView] = [];
    low = area.lower().strip();
    for b in [hub ->:Holds:->[?:Bulletin]] {
        if low == "" or low in b.area.lower() or b.area.lower() in low {
            out.append(BulletinView(issuer=b.issuer, area=b.area, text=b.text, issued_at=b.issued_at));
        }
    }
    return sorted(out, key=lambda (b: BulletinView) { b.issued_at; }, reverse=True);
}

def add_bulletin(hub: CrisisConnectHub, issuer: str, area: str, text: str) -> BulletinView {
    b = Bulletin(issuer=issuer, area=area, text=text, issued_at=hub.storm_time);
    hub +>:Holds:+> b;
    log_decision(hub, "district", "publish_bulletin", f"{issuer} bulletin for {area}", "APPLIED", hub.storm_time, [], model="human", target_label=area);
    return BulletinView(issuer=issuer, area=area, text=text, issued_at=hub.storm_time);
}

def citizen_status(hub: CrisisConnectHub, msg_id: str) -> CitizenStatus {
    msg = find_message(hub, msg_id);
    if msg is None {
        return CitizenStatus(msg_id=msg_id, found=False, stage_label="Not found", detail="Check the reference number on your receipt.");
    }
    st = CitizenStatus(msg_id=msg_id, found=True, kind=msg.kind);
    if msg.kind in ["APPEAL", "RUMOUR"] {
        for ap in [hub ->:Holds:->[?:Appeal]] {
            if ap.source_msg_id == msg_id {
                st.verdict = ap.verdict;
                st.verdict_reason = ap.reason;
            }
        }
        for rc in [hub ->:Holds:->[?:RumourClaim]] {
            if rc.source_msg_id == msg_id {
                st.verdict = rc.stance;
                st.verdict_reason = rc.claim;
            }
        }
        st.stage = 1;
        st.stage_label = "Checked";
        st.detail = "We compared this message with official bulletins and the registry of offices and groups.";
        return st;
    }
    inc = incident_of(msg);
    if inc is None {
        st.stage = 0;
        st.stage_label = "Received";
        st.detail = "Your message is in the queue. A desk will read it shortly.";
        return st;
    }
    st.inc_id = inc.inc_id;
    st.gn = inc.gn;
    ds = ds_of(inc);
    if ds is not None {
        st.ds = ds.name;
        st.officer = officer_for(ds.name);
    }
    reqs = requests_of(inc);
    st.help = [f"{r.need}: {r.status.lower()}" + (f" ({r.ngo})" if r.ngo != "" else "") for r in reqs];
    states = [r.status for r in reqs];
    vcall = verifying_call(inc);
    misses = no_answer_count(inc);
    # Stages, each earned by a real event (never by a call that went unanswered):
    # 0 received, 1 sent to division, 2 officer confirmed by phone,
    # 3 a group accepted, 4 help on the way, 5 delivered or household safe.
    if inc.status in ["RESOLVED", "HANDED_OVER"] {
        st.stage = 5;
        st.stage_label = "Marked safe";
        st.detail = "The desk has recorded that your household is safe.";
    } elif "DELIVERED" in states {
        st.stage = 5;
        st.stage_label = "Help delivered";
        st.detail = "The relief group recorded the delivery. Tell the desk if anyone still needs help.";
    } elif "DISPATCHED" in states {
        st.stage = 4;
        st.stage_label = "Help is on the way";
        st.detail = "A registered group has set off to you.";
    } elif "ACCEPTED" in states {
        st.stage = 3;
        st.stage_label = "A group accepted";
        st.detail = "A registered relief group accepted your request and is preparing.";
    } elif vcall is not None {
        st.stage = 2;
        st.stage_label = "Officer confirmed";
        st.detail = f"An officer reached your household at {vcall.storm_time} and confirmed the details.";
    } else {
        st.stage = 1;
        st.stage_label = "Sent to your division";
        st.detail = (
            f"We called {misses} time(s) and could not get through. Keep your phone on; you stay at the front of the queue."
            if misses > 0
            else f"Your request reached {st.officer or 'the district desk'}. Keep your phone on."
        );
    }
    return st;
}

# ---------- District: escalations and overview ----------

glob ESCALATE_DS_MIN: int = 30;
glob ESCALATE_DISTRICT_MIN: int = 60;

def escalation_rows(hub: CrisisConnectHub) -> list[EscalationRow] {
    out: list[EscalationRow] = [];
    for inc in all_incidents(hub) {
        if not is_open(inc) or is_verified(inc) {
            continue;
        }
        mins = storm_diff(hub.storm_time, inc.first_seen);
        misses = no_answer_count(inc);
        # Vulnerable people, or calls that went unanswered, escalate twice as fast.
        limit = ESCALATE_DS_MIN // 2 if len(inc.vulnerable) > 0 or misses > 0 else ESCALATE_DS_MIN;
        if mins < limit {
            continue;
        }
        level = "District" if mins >= ESCALATE_DISTRICT_MIN else "Division";
        ds = ds_of(inc);
        why = (f"No answer on {misses} call(s) in {fmt_minutes(mins)}" if misses > 0 else f"Not reached after {fmt_minutes(mins)}") + (", vulnerable people waiting" if len(inc.vulnerable) > 0 else "");
        out.append(EscalationRow(
            inc_id=inc.inc_id, place=inc.place, ds=ds.name if ds is not None else "Not placed",
            waiting_min=mins, waiting=fmt_minutes(mins), level=level, reason=why,
            headcount=inc.headcount, vulnerable=inc.vulnerable
        ));
    }
    return sorted(out, key=lambda (e: EscalationRow) { -e.waiting_min; });
}

def district_overview(hub: CrisisConnectHub) -> DistrictOverview {
    incs = [i for i in all_incidents(hub) if is_open(i)];
    reqs = [hub ->:Holds:->[?:ResourceRequest]];
    return DistrictOverview(
        storm_time=hub.storm_time,
        messages=len([hub ->:Holds:->[?:Message]]),
        open_incidents=len(incs),
        unanswered=len([i for i in incs if not is_verified(i)]),
        vulnerable_open=len([i for i in incs if len(i.vulnerable) > 0]),
        open_requests=len([r for r in reqs if r.status in ["REQUESTED", "ACCEPTED", "DISPATCHED"]]),
        uncovered_requests=len([r for r in reqs if r.status == "UNCOVERED"]),
        divisions=[d for d in division_views(hub) if d.open_count > 0],
        escalations=escalation_rows(hub)
    );
}
