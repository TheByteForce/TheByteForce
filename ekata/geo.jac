"""Map and routes: where every household, shelter, relief group and warning is,
and the route agent that plans a team's run.

Coordinates: DS division centres are real public geography; each incident
without a pin sits at its division centre plus a small fixed offset from its
id (so it never moves between reloads). A citizen who drops a pin gives the
exact point. Shelters and group bases are invented, like the rest of the demo.

Route agent: from a team's base it builds three candidate runs (vulnerable
first, most people, shortest drive), orders each on the road network (OSRM
trip service, straight-line fallback offline), scores how many scenarios each
covers, and picks one. With AI on, the model chooses among the three and says
why; the deterministic score is the fallback and the guard.
"""

import json;
import math;
import hashlib;
import os;
import from urllib.request { urlopen }
import from ekata.schema { EkataHub, Holds, Incident, Message, Bulletin, RegistryEntry, ResourceRequest, GNDivision, LocatedIn }
import from ekata.store { all_incidents, find_incident, find_message, incident_of, log_decision, storm_diff, fmt_minutes, has_call_log }
import from ekata.referee { OPEN_STATUSES }
import from ekata.portal { ds_of, requests_of, incident_of_request, find_ds, ngo_profile }
import from ekata.ai.models { fast, last_model }

# ---------- Places (DS division centres, public geography) ----------

glob DS_CENTRES: dict[str, list[float]] = {
    "Kegalle": [7.2513, 80.3464],
    "Mawanella": [7.2523, 80.4458],
    "Rambukkana": [7.3236, 80.3953],
    "Warakapola": [7.2266, 80.1966],
    "Aranayaka": [7.1667, 80.4667],
    "Dehiowita": [6.9700, 80.2650],
    "Yatiyantota": [7.0250, 80.3000],
    "Ratnapura": [6.6828, 80.3992],
    "Kuruwita": [6.7770, 80.3680],
    "Eheliyagoda": [6.8480, 80.2650],
    "Pelmadulla": [6.6200, 80.5420],
    "Balangoda": [6.6470, 80.7000]
};

glob COUNTRY_CENTRE: list[float] = [7.02, 80.40];

# Invented relief shelters (one or two per division).
glob SHELTERS: list[list[any]] = [
    ["Shelter: Kegalle town school hall", 7.2560, 80.3420, 300],
    ["Shelter: Mawanella temple hall", 7.2480, 80.4400, 180],
    ["Shelter: Mawanella upper school", 7.2610, 80.4520, 250],
    ["Shelter: Rambukkana community centre", 7.3200, 80.3900, 150],
    ["Shelter: Aranayaka school (high ground)", 7.1720, 80.4600, 200],
    ["Shelter: Warakapola school hall", 7.2300, 80.2000, 160],
    ["Shelter: Yatiyantota community hall", 7.0300, 80.3050, 120],
    ["Shelter: Ratnapura central school", 6.6900, 80.4050, 400],
    ["Shelter: Kuruwita school hall", 6.7800, 80.3720, 220],
    ["Shelter: Eheliyagoda temple hall", 6.8500, 80.2700, 140]
];

# Invented bases for the registered groups (where their teams start).
glob GROUP_BASES: dict[str, list[float]] = {
    "Kegalle Volunteer Kitchen": [7.2490, 80.3500],
    "Hill Country Relief Trust": [7.2400, 80.4300],
    "Hill Country Aid Circle": [7.2450, 80.3600],
    "Kelani Valley Volunteers": [7.0200, 80.2950],
    "Green Ridge Boat Volunteers": [7.2550, 80.4100],
    "Ratnapura Helping Hands Society": [6.6850, 80.4100]
};

# ---------- Views ----------

obj MapPoint {
    has id: str;
    has kind: str;
    has label: str;
    has lat: float;
    has lon: float;
    has detail: str = "";
    has tone: str = "";
    has people: int = 0;
    has vulnerable: list[str] = [];
    has status: str = "";
}

obj MapZone {
    has label: str;
    has issuer: str;
    has text: str;
    has lat: float;
    has lon: float;
    has radius_m: int;
    has tone: str;
}

obj MapLayers {
    has center: list[float];
    has zoom: int;
    has incidents: list[MapPoint] = [];
    has shelters: list[MapPoint] = [];
    has bases: list[MapPoint] = [];
    has zones: list[MapZone] = [];
    has note: str = "";
}

obj RouteStop {
    has order: int;
    has id: str;
    has label: str;
    has lat: float;
    has lon: float;
    has people: int = 0;
    has vulnerable: list[str] = [];
    has eta_min: int = 0;
    has why: str = "";
}

obj PlanOption {
    has name: str;
    has title: str;
    has stops: int;
    has people: int;
    has vulnerable_households: int;
    has oldest_covered: bool;
    has duration_min: int;
    has distance_km: float;
    has score: float;
}

obj RoutePlan {
    has ok: bool = True;
    has origin_label: str = "";
    has origin: list[float] = [];
    has chosen: str = "";
    has reason: str = "";
    has model: str = "rules";
    has stops: list[RouteStop] = [];
    has path: list[list[float]] = [];
    has distance_km: float = 0.0;
    has duration_min: int = 0;
    has people: int = 0;
    has options: list[PlanOption] = [];
    has skipped: list[str] = [];
    has road: bool = False;
}

obj NearbyPlace {
    has label: str;
    has lat: float;
    has lon: float;
    has km: float;
    has detail: str = "";
}

# ---------- Geometry ----------

def haversine_km(a: list[float], b: list[float]) -> float {
    r = 6371.0;
    p1 = math.radians(a[0]);
    p2 = math.radians(b[0]);
    dp = p2 - p1;
    dl = math.radians(b[1] - a[1]);
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2;
    return 2 * r * math.asin(math.sqrt(h));
}

def jitter(key: str) -> list[float] {
    d = hashlib.sha1(key.encode("utf-8")).digest();
    dx = (d[0] / 255.0 - 0.5) * 0.04;
    dy = (d[1] / 255.0 - 0.5) * 0.04;
    return [dy, dx];
}

def centre_for_text(text: str) -> list[float] | None {
    low = text.lower();
    for (name, c) in DS_CENTRES.items() {
        if name.lower()[:6] in low {
            return c;
        }
    }
    return None;
}

def nearest_ds(lat: float, lon: float) -> str {
    best = "";
    best_km = 1e9;
    for (name, c) in DS_CENTRES.items() {
        km = haversine_km([lat, lon], c);
        if km < best_km {
            best_km = km;
            best = name;
        }
    }
    return best;
}

# Where an incident is. Stores the derived point so it stays put.
def coords_of(inc: Incident) -> list[float] {
    if inc.lat != 0.0 or inc.lon != 0.0 {
        return [inc.lat, inc.lon];
    }
    base: list[float] | None = None;
    ds = ds_of(inc);
    if ds is not None and ds.name in DS_CENTRES {
        base = DS_CENTRES[ds.name];
    }
    if base is None {
        base = centre_for_text(inc.place + " " + inc.summary);
    }
    if base is None {
        base = COUNTRY_CENTRE;
    }
    j = jitter(inc.inc_id);
    inc.lat = round(base[0] + j[0], 5);
    inc.lon = round(base[1] + j[1], 5);
    return [inc.lat, inc.lon];
}

def in_ds(inc: Incident, name: str) -> bool {
    ds = ds_of(inc);
    return ds is not None and ds.name.lower() == name.lower();
}

def is_open(inc: Incident) -> bool {
    return inc.status in OPEN_STATUSES;
}

def incident_tone(inc: Incident) -> str {
    if not is_open(inc) {
        return "ok";
    }
    if len(inc.vulnerable) > 0 {
        return "alert";
    }
    return "info";
}

def incident_point(hub: EkataHub, inc: Incident) -> MapPoint {
    c = coords_of(inc);
    ds = ds_of(inc);
    waiting = fmt_minutes(storm_diff(hub.storm_time, inc.first_seen));
    who = f"{inc.headcount} people" if inc.headcount > 0 else "Headcount unknown";
    detail = f"{who}, waiting {waiting}" if is_open(inc) else "Reached";
    if ds is not None {
        detail = detail + f", {ds.name} division";
    }
    return MapPoint(
        id=inc.inc_id, kind="incident", label=inc.place if inc.place != "" else inc.inc_id,
        detail=detail, lat=c[0], lon=c[1], tone=incident_tone(inc),
        people=inc.headcount, vulnerable=inc.vulnerable, status=inc.status
    );
}

def shelter_points() -> list[MapPoint] {
    return [
        MapPoint(id=f"S{i}", kind="shelter", label=str(s[0]), detail=f"Room for about {s[3]} people", lat=float(s[1]), lon=float(s[2]), tone="ok")
        for (i, s) in enumerate(SHELTERS)
    ];
}

def base_points(hub: EkataHub) -> list[MapPoint] {
    out: list[MapPoint] = [];
    for reg in [hub ->:Holds:->[?:RegistryEntry]] {
        if reg.kind != "NGO" or reg.office not in GROUP_BASES {
            continue;
        }
        c = GROUP_BASES[reg.office];
        prof = ngo_profile(reg.office);
        out.append(MapPoint(id=reg.office, kind="base", label=reg.office, detail="Offers " + ", ".join(prof["offers"]), lat=c[0], lon=c[1], tone="info"));
    }
    return out;
}

def zone_points(hub: EkataHub) -> list[MapZone] {
    out: list[MapZone] = [];
    for b in [hub ->:Holds:->[?:Bulletin]] {
        c: list[float] | None = DS_CENTRES.get(b.area, None);
        if c is None {
            c = centre_for_text(b.area + " " + b.text);
        }
        if c is None {
            continue;
        }
        tone = "alert" if b.issuer in ["Landslide Watch", "Reservoir Office"] else "info";
        out.append(MapZone(label=f"{b.issuer} {b.area}", issuer=b.issuer, text=b.text, lat=c[0], lon=c[1], radius_m=7000 if b.issuer == "Landslide Watch" else 9000, tone=tone));
    }
    return out;
}

# scope: "all", "ds:<name>", "ngo:<office>", "area:<name>"
def map_layers_for(hub: EkataHub, scope: str) -> MapLayers {
    incs = [i for i in all_incidents(hub)];
    center = COUNTRY_CENTRE;
    zoom = 9;
    note = "";
    if scope.startswith("ds:") {
        name = scope[3:];
        incs = [i for i in incs if in_ds(i, name)];
        if name in DS_CENTRES {
            center = DS_CENTRES[name];
            zoom = 12;
        }
    } elif scope.startswith("ngo:") {
        office = scope[4:];
        keep: list[str] = [];
        for r in [hub ->:Holds:->[?:ResourceRequest]] {
            if r.ngo == office {
                inc = incident_of_request(r);
                if inc is not None {
                    keep.append(inc.inc_id);
                }
            }
        }
        incs = [i for i in incs if i.inc_id in keep];
        if office in GROUP_BASES {
            center = GROUP_BASES[office];
            zoom = 11;
        }
    } elif scope.startswith("area:") {
        name = scope[5:];
        if name in DS_CENTRES {
            center = DS_CENTRES[name];
            zoom = 12;
        }
        note = "Households are shown without names or numbers.";
    }
    points = [incident_point(hub, i) for i in incs];
    if scope.startswith("area:") {
        for p in points {
            p.label = "A household asked for help";
            p.vulnerable = [];
        }
    }
    return MapLayers(
        center=center, zoom=zoom, incidents=points, shelters=shelter_points(),
        bases=base_points(hub), zones=zone_points(hub), note=note
    );
}

# ---------- Citizen pin ----------

def pin_report(hub: EkataHub, msg_id: str, lat: float, lon: float) -> str {
    msg = find_message(hub, msg_id);
    if msg is None {
        return "";
    }
    inc = incident_of(msg);
    if inc is None {
        return "";
    }
    inc.lat = round(lat, 5);
    inc.lon = round(lon, 5);
    if ds_of(inc) is None {
        target = f"{nearest_ds(lat, lon)} (GN not stated)";
        for gn in [hub ->:Holds:->[?:GNDivision]] {
            if gn.name == target {
                inc +>:LocatedIn:+> gn;
                inc.gn = gn.name;
            }
        }
    }
    log_decision(hub, "citizen", "pin_location", f"Citizen dropped a pin for {inc.inc_id} near {nearest_ds(lat, lon)}", "APPLIED", hub.storm_time, [inc], confidence=1.0, model="human", target_label=inc.inc_id);
    return nearest_ds(lat, lon);
}

def nearby_shelters(lat: float, lon: float) -> list[NearbyPlace] {
    rows = [
        NearbyPlace(label=str(s[0]), lat=float(s[1]), lon=float(s[2]), km=round(haversine_km([lat, lon], [float(s[1]), float(s[2])]), 1), detail=f"Room for about {s[3]} people")
        for s in SHELTERS
    ];
    return sorted(rows, key=lambda (p: NearbyPlace) { p.km; })[:3];
}

# ---------- Route agent ----------

obj Candidate {
    has id: str;
    has label: str;
    has lat: float;
    has lon: float;
    has people: int;
    has vulnerable: list[str];
    has waiting_min: int;
    has priority: float;
}

obj Ordered {
    has order: list[int];
    has path: list[list[float]];
    has legs_min: list[int];
    has distance_km: float;
    has duration_min: int;
    has road: bool;
    has snapped: list[list[float]] = [];
}

obj PlanPick {
    has name: str;
    has reason: str;
}

sem PlanPick.name = "Exactly one plan name from the options: vulnerable_first, most_people or shortest.";
sem PlanPick.reason = "One plain sentence for a rescue team lead: why this run, what it covers and what it leaves for the next run.";

def choose_plan(team: str, options: list[PlanOption]) -> PlanPick by fast(
    temperature=0.0,
    incl_info={"policy": "Pick the run that covers the most scenarios tonight: vulnerable households first, then the most people, then the longest-waiting household, then drive time. Never pick a run that leaves a vulnerable household behind when another run reaches it in similar time."}
);

glob ROUTE_CACHE: dict[str, Ordered] = {};

def straight_order(origin: list[float], pts: list[Candidate]) -> Ordered {
    left = list(range(len(pts)));
    order: list[int] = [];
    cur = origin;
    legs: list[int] = [];
    total = 0.0;
    path = [origin];
    while len(left) > 0 {
        best = left[0];
        best_km = 1e9;
        for i in left {
            km = haversine_km(cur, [pts[i].lat, pts[i].lon]);
            if km < best_km {
                best_km = km;
                best = i;
            }
        }
        left.remove(best);
        order.append(best);
        road_km = best_km * 1.4;
        total += road_km;
        legs.append(int(round(road_km / 25.0 * 60)));
        cur = [pts[best].lat, pts[best].lon];
        path.append(cur);
    }
    return Ordered(order=order, path=path, legs_min=legs, distance_km=round(total, 1), duration_min=sum(legs), road=False);
}

# Road order from OSRM's trip service (origin fixed first, no return leg).
def road_order(origin: list[float], pts: list[Candidate]) -> Ordered {
    if len(pts) == 0 {
        return Ordered(order=[], path=[origin], legs_min=[], distance_km=0.0, duration_min=0, road=False);
    }
    coords = [origin] + [[p.lat, p.lon] for p in pts];
    key = ";".join([f"{c[1]:.5f},{c[0]:.5f}" for c in coords]);
    if key in ROUTE_CACHE {
        return ROUTE_CACHE[key];
    }
    base = os.environ.get("EKATA_OSRM_URL", "https://router.project-osrm.org");
    url = f"{base}/trip/v1/driving/{key}?source=first&roundtrip=false&destination=any&overview=simplified&geometries=geojson";
    try {
        with urlopen(url, timeout=6) as resp {
            data = json.loads(resp.read().decode("utf-8"));
        }
        if data.get("code") != "Ok" {
            return straight_order(origin, pts);
        }
        wps = data["waypoints"];
        # waypoint_index is each input point's position in the trip; input 0 is the origin.
        pos = [(int(wps[i]["waypoint_index"]), i - 1) for i in range(1, len(wps))];
        order = [p[1] for p in sorted(pos)];
        snapped = [[float(wps[i]["location"][1]), float(wps[i]["location"][0])] for i in range(1, len(wps))];
        trip = data["trips"][0];
        path = [[float(c[1]), float(c[0])] for c in trip["geometry"]["coordinates"]];
        legs = [int(round(float(l["duration"]) / 60.0)) for l in trip["legs"]];
        out = Ordered(order=order, path=path, legs_min=legs, distance_km=round(float(trip["distance"]) / 1000.0, 1), duration_min=int(round(float(trip["duration"]) / 60.0)), road=True, snapped=snapped);
        ROUTE_CACHE[key] = out;
        return out;
    } except Exception {
        return straight_order(origin, pts);
    }
}

def plan_score(opt: PlanOption) -> float {
    return 3.0 * opt.vulnerable_households + opt.people / 4.0 + (2.0 if opt.oldest_covered else 0.0) + opt.stops - opt.duration_min / 30.0;
}

def pick_set(name: str, origin: list[float], cands: list[Candidate], max_stops: int) -> list[Candidate] {
    if name == "vulnerable_first" {
        ranked = sorted(cands, key=lambda (c: Candidate) { (0 if len(c.vulnerable) > 0 else 1, -c.priority, -c.waiting_min); });
        return ranked[:max_stops];
    }
    if name == "most_people" {
        ranked = sorted(cands, key=lambda (c: Candidate) { (-c.people, -c.priority); });
        return ranked[:max_stops];
    }
    # shortest: nearest neighbour from the base
    left = list(cands);
    out: list[Candidate] = [];
    cur = origin;
    while len(left) > 0 and len(out) < max_stops {
        best = left[0];
        for c in left {
            if haversine_km(cur, [c.lat, c.lon]) < haversine_km(cur, [best.lat, best.lon]) {
                best = c;
            }
        }
        left.remove(best);
        out.append(best);
        cur = [best.lat, best.lon];
    }
    return out;
}

glob PLAN_TITLES: dict[str, str] = {
    "vulnerable_first": "Vulnerable households first",
    "most_people": "Most people",
    "shortest": "Shortest drive"
};

def plan_run(hub: EkataHub, team: str, origin_label: str, origin: list[float], cands: list[Candidate], max_stops: int) -> RoutePlan {
    if len(cands) == 0 {
        return RoutePlan(ok=False, origin_label=origin_label, origin=origin, reason="Nobody is waiting on this run.");
    }
    oldest = max(cands, key=lambda (c: Candidate) { c.waiting_min; }).id;
    built: dict[str, list[any]] = {};
    options: list[PlanOption] = [];
    for name in ["vulnerable_first", "most_people", "shortest"] {
        chosen = pick_set(name, origin, cands, max_stops);
        ordered = road_order(origin, chosen);
        opt = PlanOption(
            name=name, title=PLAN_TITLES[name], stops=len(chosen),
            people=sum([c.people for c in chosen]),
            vulnerable_households=len([c for c in chosen if len(c.vulnerable) > 0]),
            oldest_covered=oldest in [c.id for c in chosen],
            duration_min=ordered.duration_min, distance_km=ordered.distance_km, score=0.0
        );
        opt.score = round(plan_score(opt), 2);
        options.append(opt);
        built[name] = [chosen, ordered];
    }
    best = max(options, key=lambda (o: PlanOption) { o.score; });
    reason = f"{best.title}: reaches {best.vulnerable_households} households with vulnerable people and {best.people} people in about {best.duration_min} min.";
    model = "rules";
    if os.environ.get("EKATA_AI", "on").lower() != "off" {
        try {
            pick = choose_plan(team, options);
            names = [o.name for o in options];
            if pick.name in names {
                cand = options[names.index(pick.name)];
                # Guard: never leave vulnerable households behind for a worse run.
                if cand.vulnerable_households >= best.vulnerable_households {
                    best = cand;
                    reason = pick.reason;
                    model = last_model() or "llm";
                }
            }
        } except Exception {
            model = "rules";
        }
    }
    chosen = built[best.name][0];
    ordered = built[best.name][1];
    stops: list[RouteStop] = [];
    eta = 0;
    for (k, idx) in enumerate(ordered.order) {
        c = chosen[idx];
        if k < len(ordered.legs_min) {
            eta += ordered.legs_min[k];
        }
        why = "Vulnerable: " + ", ".join(c.vulnerable) if len(c.vulnerable) > 0 else (f"{c.people} people" if c.people > 0 else "Headcount unknown");
        if c.id == oldest {
            why = why + "; waiting longest";
        }
        at = ordered.snapped[idx] if idx < len(ordered.snapped) else [c.lat, c.lon];
        stops.append(RouteStop(order=k + 1, id=c.id, label=c.label, lat=at[0], lon=at[1], people=c.people, vulnerable=c.vulnerable, eta_min=eta, why=why));
    }
    left_out = [c for c in cands if c.id not in [s.id for s in stops]];
    skipped = [f"{c.label} ({'vulnerable' if len(c.vulnerable) > 0 else str(c.people) + ' people'})" for c in left_out][:6];
    log_decision(hub, "router", "plan_route", f"{team}: {reason}", "APPLIED", hub.storm_time, [], confidence=0.8, model=model, target_label=team);
    return RoutePlan(
        ok=True, origin_label=origin_label, origin=origin, chosen=best.name, reason=reason, model=model,
        stops=stops, path=ordered.path, distance_km=ordered.distance_km, duration_min=ordered.duration_min,
        people=best.people, options=options, skipped=skipped, road=ordered.road
    );
}

def candidate_of(hub: EkataHub, inc: Incident) -> Candidate {
    c = coords_of(inc);
    return Candidate(
        id=inc.inc_id, label=inc.place if inc.place != "" else inc.inc_id, lat=c[0], lon=c[1],
        people=inc.headcount, vulnerable=inc.vulnerable,
        waiting_min=storm_diff(hub.storm_time, inc.first_seen), priority=inc.priority
    );
}

def plan_for_division(hub: EkataHub, ds_name: str, max_stops: int) -> RoutePlan {
    origin = DS_CENTRES.get(ds_name, COUNTRY_CENTRE);
    cands = [candidate_of(hub, i) for i in all_incidents(hub) if is_open(i) and in_ds(i, ds_name)];
    return plan_run(hub, f"{ds_name} rescue team", f"{ds_name} divisional office", origin, cands, max_stops);
}

def plan_for_group(hub: EkataHub, office: str, max_stops: int) -> RoutePlan {
    origin = GROUP_BASES.get(office, COUNTRY_CENTRE);
    cands: list[Candidate] = [];
    seen: list[str] = [];
    for r in [hub ->:Holds:->[?:ResourceRequest]] {
        if r.ngo != office or r.status not in ["REQUESTED", "ACCEPTED", "DISPATCHED"] {
            continue;
        }
        inc = incident_of_request(r);
        if inc is not None and inc.inc_id not in seen {
            seen.append(inc.inc_id);
            cands.append(candidate_of(hub, inc));
        }
    }
    return plan_run(hub, office, f"{office} base", origin, cands, max_stops);
}
