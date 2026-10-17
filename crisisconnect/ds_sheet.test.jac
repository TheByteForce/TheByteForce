"""DS sheet tests, each on a private hub with a tiny hand-built admin spine."""

import from crisisconnect.store { fresh_hub }

def mk_spine(hub: CrisisConnectHub, ds_name: str, gn_name: str, dist_name: str) -> GNDivision {
    d = District(name=dist_name);
    ds = DSDivision(name=ds_name);
    gn = GNDivision(name=gn_name);
    hub +>:Holds:+> d;
    hub +>:Holds:+> ds;
    hub +>:Holds:+> gn;
    gn +>:InDS:+> ds;
    ds +>:InDistrict:+> d;
    return gn;
}

def mk_inc(hub: CrisisConnectHub, gn: GNDivision, iid: str, status: str, heads: int, vuln: list[str]) -> Incident {
    inc = Incident(inc_id=iid, status=status, headcount=heads, vulnerable=vuln, gn=gn.name, place="Temple Road");
    hub +>:Holds:+> inc;
    inc +>:LocatedIn:+> gn;
    return inc;
}

test "a confirmed incident appears with GN and district" {
    hub = fresh_hub("t-ds1");
    gn = mk_spine(hub, "Mawanella", "Hettimulla", "Kegalle");
    mk_inc(hub, gn, "INC-001", "CONFIRMED", 4, ["elderly"]);
    s = build_ds_sheet(hub, "Mawanella");
    assert s.confirmed == 1;
    assert s.district == "Kegalle";
    assert s.rows[0].gn == "Hettimulla";
    assert s.rows[0].inc_id == "INC-001";
    assert s.rows[0].last_call == "";
    assert "phone-verified" in s.note;
}

test "an unconfirmed incident counts as open but is not a row" {
    hub = fresh_hub("t-ds2");
    gn = mk_spine(hub, "Mawanella", "Hettimulla", "Kegalle");
    mk_inc(hub, gn, "INC-001", "CONFIRMED", 2, []);
    mk_inc(hub, gn, "INC-002", "NEW", 6, []);
    mk_inc(hub, gn, "INC-003", "RESOLVED", 3, []);
    s = build_ds_sheet(hub, "Mawanella");
    assert s.confirmed == 1;
    assert s.open_count == 2;
    assert len(s.rows) == 1;
}

test "another DS is excluded and rows sort vulnerable first" {
    hub = fresh_hub("t-ds3");
    g1 = mk_spine(hub, "Mawanella", "Hettimulla", "Kegalle");
    g2 = mk_spine(hub, "Kegalle", "Town", "Kegalle");
    mk_inc(hub, g1, "INC-001", "CONFIRMED", 8, []);
    mk_inc(hub, g1, "INC-002", "HANDED_OVER", 2, ["infant"]);
    mk_inc(hub, g2, "INC-003", "CONFIRMED", 5, []);
    s = build_ds_sheet(hub, "Mawanella");
    assert len(s.rows) == 2;
    assert s.rows[0].inc_id == "INC-002";
    assert s.rows[1].inc_id == "INC-001";
}

test "last call fields come from the newest CallLog" {
    hub = fresh_hub("t-ds4");
    gn = mk_spine(hub, "Mawanella", "Hettimulla", "Kegalle");
    inc = mk_inc(hub, gn, "INC-001", "CONFIRMED", 4, []);
    c1 = CallLog(outcome="REACHED_CONFIRMED", desk="desk-1", storm_time="18:10");
    c2 = CallLog(outcome="STILL_IN_NEED", desk="desk-2", storm_time="19:30");
    hub +>:Holds:+> c1;
    hub +>:Holds:+> c2;
    c1 +>:Logged:+> inc;
    c2 +>:Logged:+> inc;
    s = build_ds_sheet(hub, "Mawanella");
    assert s.rows[0].last_call == "STILL_IN_NEED";
    assert s.rows[0].last_desk == "desk-2";
}

test "ds_summary counts and orders divisions" {
    hub = fresh_hub("t-ds5");
    g1 = mk_spine(hub, "Mawanella", "Hettimulla", "Kegalle");
    g2 = mk_spine(hub, "Kegalle", "Town", "Kegalle");
    mk_spine(hub, "Empty", "Nowhere", "Kegalle");
    mk_inc(hub, g1, "INC-001", "CONFIRMED", 4, []);
    mk_inc(hub, g1, "INC-002", "CONFIRMED", 3, []);
    mk_inc(hub, g2, "INC-003", "NEW", 5, []);
    r = ds_summary(hub);
    assert len(r) == 2;
    assert r[0].ds == "Mawanella";
    assert r[0].confirmed == 2;
    assert r[0].open_count == 2;
    assert r[1].ds == "Kegalle";
    assert r[1].confirmed == 0;
    assert r[1].open_count == 1;
}
