"""CrisisConnect DS hand-over sheet: a clean per-Divisional-Secretariat picture of
phone-verified incidents for DS/GN officers. Read-only.

Note: the count of open incidents is named open_count (not open) to avoid the
Python builtin.
"""

import from crisisconnect.schema {
    CrisisConnectHub, Incident, GNDivision, DSDivision, District, CallLog,
    LocatedIn, InDS, InDistrict, Logged, Holds
}
import from crisisconnect.store { all_incidents, storm_minutes }
import from crisisconnect.referee { OPEN_STATUSES }

obj SheetRow {
    has inc_id: str;
    has gn: str;
    has status: str;
    has headcount: int;
    has vulnerable: list[str];
    has needs: list[str];
    has place: str;
    has last_call: str;
    has last_desk: str;
}

obj DsSheet {
    has ds: str;
    has district: str;
    has storm_time: str;
    has confirmed: int;
    has open_count: int;
    has rows: list[SheetRow];
    has note: str;
}

obj DsCount {
    has ds: str;
    has district: str;
    has confirmed: int;
    has open_count: int;
}

def ds_of_incident(inc: Incident) -> DSDivision | None {
    for gn in [inc ->:LocatedIn:->[?:GNDivision]] {
        for ds in [gn ->:InDS:->[?:DSDivision]] {
            return ds;
        }
    }
    return None;
}

def district_of_ds(ds: DSDivision) -> str {
    for d in [ds ->:InDistrict:->[?:District]] {
        return d.name;
    }
    return "";
}

def newest_call(inc: Incident) -> CallLog | None {
    best: CallLog | None = None;
    best_t = -1;
    for c in [inc <-:Logged:<-[?:CallLog]] {
        t = storm_minutes(c.storm_time);
        if best is None or t >= best_t {
            best = c;
            best_t = t;
        }
    }
    return best;
}

def build_ds_sheet(hub: CrisisConnectHub, ds_name: str) -> DsSheet {
    rows: list[SheetRow] = [];
    open_n = 0;
    district = "";
    for inc in all_incidents(hub) {
        ds = ds_of_incident(inc);
        if ds is None or ds.name != ds_name {
            continue;
        }
        if district == "" {
            district = district_of_ds(ds);
        }
        if inc.status in OPEN_STATUSES {
            open_n += 1;
        }
        if inc.status == "CONFIRMED" or inc.status == "HANDED_OVER" {
            lc = "";
            ld = "";
            c = newest_call(inc);
            if c is not None {
                lc = c.outcome;
                ld = c.desk;
            }
            rows.append(SheetRow(
                inc_id=inc.inc_id, gn=inc.gn, status=inc.status, headcount=inc.headcount,
                vulnerable=inc.vulnerable, needs=inc.needs, place=inc.place,
                last_call=lc, last_desk=ld
            ));
        }
    }
    rows = sorted(rows, key=lambda (r: SheetRow) {
        (0 if len(r.vulnerable) > 0 else 1, -r.headcount, r.inc_id);
    });
    return DsSheet(
        ds=ds_name, district=district, storm_time=hub.storm_time,
        confirmed=len(rows), open_count=open_n, rows=rows,
        note="Only phone-verified incidents are listed."
    );
}

def ds_summary(hub: CrisisConnectHub) -> list[DsCount] {
    names: list[str] = [];
    for inc in all_incidents(hub) {
        ds = ds_of_incident(inc);
        if ds is not None and ds.name not in names {
            names.append(ds.name);
        }
    }
    out: list[DsCount] = [];
    for n in names {
        s = build_ds_sheet(hub, n);
        out.append(DsCount(ds=n, district=s.district, confirmed=s.confirmed, open_count=s.open_count));
    }
    return sorted(out, key=lambda (c: DsCount) { (-c.confirmed, -c.open_count, c.ds); });
}
