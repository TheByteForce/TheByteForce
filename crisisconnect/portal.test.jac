"""Portal tests: division routing, the NGO matcher, citizen stages, escalations."""

import os;
import from crisisconnect.store { fresh_hub }
import from crisisconnect.seed { seed_spine, seed_registry }
import from crisisconnect.schema { PartOf, Logged, Decision }

def must(r: ResourceRequest | None) -> ResourceRequest {
    if r is None {
        raise ValueError("no request");
    }
    return r;
}

def mk_hub(name: str) -> CrisisConnectHub {
    os.environ["CRISISCONNECT_AI"] = "off";
    hub = fresh_hub(name);
    seed_spine(hub);
    seed_registry(hub);
    return hub;
}

def mk_inc(hub: CrisisConnectHub, iid: str, ds_name: str, vulnerable: list[str] = []) -> Incident {
    inc = Incident(inc_id=iid, status="NEW", headcount=4, vulnerable=vulnerable, place="12 temple road", first_seen="18:10", last_seen="18:10");
    hub +>:Holds:+> inc;
    for gn in [hub ->:Holds:->[?:GNDivision]] {
        if gn.name == f"{ds_name} (GN not stated)" {
            inc +>:LocatedIn:+> gn;
            inc.gn = gn.name;
        }
    }
    return inc;
}

test "officer queue only holds its own division" {
    hub = mk_hub("t-po-q");
    mk_inc(hub, "INC-001", "Mawanella");
    mk_inc(hub, "INC-002", "Kegalle");
    ids = [r.inc_id for r in officer_rows(hub, "Mawanella")];
    assert ids == ["INC-001"];
    views = [d for d in division_views(hub) if d.ds == "Mawanella"];
    assert views[0].open_count == 1;
    assert views[0].unanswered == 1;
}

test "pinning a GN division moves the incident" {
    hub = mk_hub("t-po-gn");
    inc = mk_inc(hub, "INC-001", "Mawanella");
    assert pin_gn(hub, "INC-001", "Mawanella North", "Divisional desk, Mawanella");
    assert inc.gn == "Mawanella North";
    assert len([inc ->:LocatedIn:->]) == 1;
    assert not pin_gn(hub, "INC-001", "Nowhere", "x");
}

test "matcher prefers a group serving the division that offers the need" {
    hub = mk_hub("t-po-m");
    mk_inc(hub, "INC-001", "Mawanella", ["elderly"]);
    req = must(create_request(hub, "INC-001", "we need a boat", "Divisional desk, Mawanella"));
    assert req is not None;
    assert req.need == "boat";
    assert req.status == "REQUESTED";
    assert req.ngo in ["Green Ridge Boat Volunteers", "Hill Country Relief Trust"];
    again = must(create_request(hub, "INC-001", "boat", "Divisional desk, Mawanella"));
    assert again.req_id == req.req_id;
}

test "decline re-routes to the next group, then uncovered" {
    hub = mk_hub("t-po-d");
    mk_inc(hub, "INC-001", "Mawanella");
    req = must(create_request(hub, "INC-001", "boat", "desk"));
    seen: list[str] = [];
    for i in range(10) {
        if req.status == "UNCOVERED" {
            break;
        }
        assert req.ngo not in seen;
        seen.append(req.ngo);
        answer_request(hub, req.req_id, req.ngo, "decline");
    }
    assert req.status == "UNCOVERED";
    assert len(seen) >= 2;
}

test "only the assigned group can answer a request" {
    hub = mk_hub("t-po-a");
    mk_inc(hub, "INC-001", "Mawanella");
    req = must(create_request(hub, "INC-001", "boat", "desk"));
    assert answer_request(hub, req.req_id, "Someone Else", "accept") is None;
    answer_request(hub, req.req_id, req.ngo, "accept");
    assert req.status == "ACCEPTED";
}

test "citizen stages follow the request" {
    hub = mk_hub("t-po-c");
    inc = mk_inc(hub, "INC-001", "Mawanella");
    m = Message(msg_id="m001", text="help", kind="SOS", seq=1);
    hub +>:Holds:+> m;
    m +>:PartOf:+> inc;
    assert citizen_status(hub, "m001").stage == 1;
    assert citizen_status(hub, "m001").ds == "Mawanella";
    req = must(create_request(hub, "INC-001", "boat", "desk"));
    answer_request(hub, req.req_id, req.ngo, "accept");
    st = citizen_status(hub, "m001");
    assert st.stage == 3;
    assert len(st.help) == 1;
    assert not citizen_status(hub, "nope").found;
}

test "unanswered vulnerable households escalate sooner" {
    hub = mk_hub("t-po-e");
    mk_inc(hub, "INC-001", "Mawanella", ["child"]);
    mk_inc(hub, "INC-002", "Kegalle");
    hub.storm_time = "18:30";
    ids = [e.inc_id for e in escalation_rows(hub)];
    assert ids == ["INC-001"];
    hub.storm_time = "19:20";
    rows = escalation_rows(hub);
    assert len(rows) == 2;
    assert rows[0].level == "District";
}

def mk_call(hub: CrisisConnectHub, inc: Incident, outcome: str, t: str) {
    c = CallLog(outcome=outcome, desk="desk", storm_time=t);
    hub +>:Holds:+> c;
    c +>:Logged:+> inc;
}

test "an unanswered call never counts as officer confirmation" {
    hub = mk_hub("t-po-na");
    inc = mk_inc(hub, "INC-001", "Mawanella");
    m = Message(msg_id="m001", text="help", kind="SOS", seq=1);
    hub +>:Holds:+> m;
    m +>:PartOf:+> inc;
    mk_call(hub, inc, "NO_ANSWER", "18:20");
    st = citizen_status(hub, "m001");
    assert st.stage == 1;
    assert "could not get through" in st.detail;
    hub.storm_time = "18:30";
    assert "INC-001" in [e.inc_id for e in escalation_rows(hub)];
    mk_call(hub, inc, "REACHED_CONFIRMED", "18:40");
    assert citizen_status(hub, "m001").stage == 2;
    assert "INC-001" not in [e.inc_id for e in escalation_rows(hub)];
}

test "accepted, dispatched and delivered are separate stages" {
    hub = mk_hub("t-po-st");
    inc = mk_inc(hub, "INC-001", "Mawanella");
    m = Message(msg_id="m001", text="help", kind="SOS", seq=1);
    hub +>:Holds:+> m;
    m +>:PartOf:+> inc;
    req = must(create_request(hub, "INC-001", "boat", "desk"));
    answer_request(hub, req.req_id, req.ngo, "accept");
    assert citizen_status(hub, "m001").stage == 3;
    answer_request(hub, req.req_id, req.ngo, "dispatched");
    assert citizen_status(hub, "m001").stage == 4;
    answer_request(hub, req.req_id, req.ngo, "delivered");
    assert citizen_status(hub, "m001").stage_label == "Help delivered";
}

test "only eligible groups are offered a request" {
    hub = mk_hub("t-po-el");
    mk_inc(hub, "INC-001", "Mawanella");
    names = [c.office for c in rank_candidates(hub, "boat", "Mawanella", "Kegalle", [])];
    assert "Kegalle Volunteer Kitchen" not in names;
    assert len(names) > 0;
    for n in names {
        assert "boat" in ngo_profile(n)["offers"];
    }
    req = must(create_request(hub, "INC-001", "shelter", "desk"));
    assert req.ngo == "Kegalle Volunteer Kitchen";
}

test "no eligible group goes straight to the district" {
    hub = mk_hub("t-po-ne");
    mk_inc(hub, "INC-001", "Balangoda");
    req = must(create_request(hub, "INC-001", "water", "desk"));
    assert req.status == "UNCOVERED";
    assert "No registered group offers" in req.reason;
}

test "a second request for the same need is blocked" {
    hub = mk_hub("t-po-dup");
    mk_inc(hub, "INC-001", "Mawanella");
    a = must(create_request(hub, "INC-001", "boat", "desk"));
    answer_request(hub, a.req_id, a.ngo, "accept");
    b = must(create_request(hub, "INC-001", "boat", "desk"));
    assert b.req_id == a.req_id;
    assert len([d for d in [hub ->:Holds:->[?:Decision]] if d.action == "duplicate_blocked"]) == 1;
}
