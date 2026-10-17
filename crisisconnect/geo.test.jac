"""Geo tests: stable coordinates, citizen pins, and the route agent's choices.
Run offline: the road service is pointed at a closed port, so routes use the
straight-line fallback."""

import os;
import from crisisconnect.store { fresh_hub }
import from crisisconnect.seed { seed_spine, seed_registry }
import from crisisconnect.schema { PartOf, LocatedIn, GNDivision }

def geo_hub(name: str) -> CrisisConnectHub {
    os.environ["CRISISCONNECT_AI"] = "off";
    os.environ["CRISISCONNECT_OSRM_URL"] = "http://127.0.0.1:9";
    hub = fresh_hub(name);
    seed_spine(hub);
    seed_registry(hub);
    return hub;
}

def put(hub: CrisisConnectHub, iid: str, ds_name: str, people: int, vulnerable: list[str], seen: str) -> Incident {
    inc = Incident(inc_id=iid, status="NEW", headcount=people, vulnerable=vulnerable, place=f"{iid} road", first_seen=seen, last_seen=seen);
    hub +>:Holds:+> inc;
    for gn in [hub ->:Holds:->[?:GNDivision]] {
        if gn.name == f"{ds_name} (GN not stated)" {
            inc +>:LocatedIn:+> gn;
            inc.gn = gn.name;
        }
    }
    return inc;
}

test "incident coordinates are stable and near the division" {
    hub = geo_hub("t-geo-c");
    inc = put(hub, "INC-001", "Mawanella", 3, [], "18:10");
    a = coords_of(inc);
    b = coords_of(inc);
    assert a == b;
    assert haversine_km(a, DS_CENTRES["Mawanella"]) < 4.0;
}

test "a citizen pin places the household and its division" {
    hub = geo_hub("t-geo-p");
    inc = Incident(inc_id="INC-001", status="NEW", first_seen="18:10", last_seen="18:10");
    hub +>:Holds:+> inc;
    m = Message(msg_id="m001", text="help", kind="SOS", seq=1);
    hub +>:Holds:+> m;
    m +>:PartOf:+> inc;
    assert pin_report(hub, "m001", 7.2601, 80.4502) == "Mawanella";
    assert inc.lat == 7.2601;
    assert inc.gn == "Mawanella (GN not stated)";
}

test "route agent puts vulnerable households on the run" {
    hub = geo_hub("t-geo-r");
    put(hub, "INC-001", "Mawanella", 2, ["elderly"], "18:00");
    put(hub, "INC-002", "Mawanella", 9, [], "18:30");
    put(hub, "INC-003", "Mawanella", 8, [], "18:40");
    put(hub, "INC-004", "Mawanella", 1, ["child"], "18:50");
    plan = plan_for_division(hub, "Mawanella", 2);
    assert plan.ok;
    ids = [s.id for s in plan.stops];
    assert "INC-001" in ids;
    assert "INC-004" in ids;
    assert len(plan.options) == 3;
    assert plan.chosen == "vulnerable_first";
    assert not plan.road;
    assert [s.order for s in plan.stops] == [1, 2];
    assert plan.stops[1].eta_min >= plan.stops[0].eta_min;
}

test "without vulnerable people the run with most people wins" {
    hub = geo_hub("t-geo-m");
    put(hub, "INC-001", "Kegalle", 1, [], "18:00");
    put(hub, "INC-002", "Kegalle", 12, [], "18:30");
    put(hub, "INC-003", "Kegalle", 10, [], "18:40");
    plan = plan_for_division(hub, "Kegalle", 2);
    ids = [s.id for s in plan.stops];
    assert "INC-002" in ids;
    assert "INC-003" in ids;
    assert len(plan.skipped) == 1;
}

test "an empty division gives a plain answer" {
    hub = geo_hub("t-geo-e");
    plan = plan_for_division(hub, "Kegalle", 5);
    assert not plan.ok;
    assert "Nobody" in plan.reason;
}

test "map layers scope to a division and hide details for citizens" {
    hub = geo_hub("t-geo-l");
    put(hub, "INC-001", "Mawanella", 2, ["elderly"], "18:00");
    put(hub, "INC-002", "Kegalle", 3, [], "18:00");
    ds_layers = map_layers_for(hub, "ds:Mawanella");
    assert [p.id for p in ds_layers.incidents] == ["INC-001"];
    area = map_layers_for(hub, "area:Mawanella");
    assert area.incidents[0].label == "A household asked for help";
    assert len(area.shelters) > 0;
}
