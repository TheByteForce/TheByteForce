"""Alert level tests: one per rule, plus the board ordering."""

import from crisisconnect.schema { Incident, Holds }
import from crisisconnect.store { fresh_hub }

def mk_inc(iid: str, needs: list[str], vul: list[str], first: str, status: str = "NEW", pri: float = 0.0) -> Incident {
    return Incident(inc_id=iid, status=status, needs=needs, vulnerable=vul, first_seen=first, priority=pri);
}

test "medical flag is level 5" {
    a = alert_for(mk_inc("A", [], ["medical"], "20:00"), "20:05");
    assert a.level == 5;
    assert a.action == "Call immediately";
}

test "elderly with a boat need and a long wait is level 5" {
    inc = mk_inc("A", ["boat"], ["elderly"], "20:00");
    assert alert_for(inc, "21:00").level == 5;
    assert alert_for(inc, "20:30").level == 4;
}

test "rescue need alone is level 4" {
    a = alert_for(mk_inc("A", ["rescue"], [], "20:00"), "23:00");
    assert a.level == 4;
    assert a.label == "Level 4 · Rescue needed";
}

test "elderly without a rescue need is level 3" {
    assert alert_for(mk_inc("A", ["food"], ["elderly"], "20:00"), "23:00").level == 3;
}

test "plain incident is level 2 verify" {
    a = alert_for(mk_inc("A", ["food"], [], "20:00"), "20:10");
    assert a.level == 2;
    assert a.action == "Verify by call when free";
}

test "close proposed is level 2 confirm and resolved is level 1" {
    assert alert_for(mk_inc("A", ["boat"], ["child"], "20:00", "CLOSE_PROPOSED"), "22:00").level == 2;
    assert alert_for(mk_inc("B", ["boat"], ["child"], "20:00", "RESOLVED"), "22:00").level == 1;
    assert alert_for(mk_inc("C", [], [], "20:00", "HANDED_OVER"), "22:00").level == 1;
}

test "alert board orders by level then priority and hides closed" {
    hub = fresh_hub("alert-test");
    hub.storm_time = "21:30";
    for inc in [
        mk_inc("P2", [], [], "21:00", "NEW", 5.0),
        mk_inc("R4lo", ["rescue"], [], "21:00", "NEW", 10.0),
        mk_inc("R4hi", ["rescue"], [], "21:00", "NEW", 40.0),
        mk_inc("M5", [], ["medical"], "21:00", "NEW", 1.0),
        mk_inc("DONE", ["boat"], [], "21:00", "RESOLVED", 99.0)
    ] {
        hub +>:Holds:+> inc;
    }
    ids = [r.inc_id for r in alert_board(hub)];
    assert ids == ["M5", "R4hi", "R4lo", "P2"];
}

test "an admin override sets the level and the latest one wins" {
    hub = fresh_hub("t-al-override");
    a = Incident(inc_id="INC-801", status="NEW", needs=["food"], priority=10.0);
    b = Incident(inc_id="INC-802", status="NEW", needs=["rescue"], priority=40.0);
    hub +>:Holds:+> a;
    hub +>:Holds:+> b;
    add_override(hub, "INC-801", 4, "road cut, family isolated", "District desk");
    rows = alert_board(hub);
    row = [r for r in rows if r.inc_id == "INC-801"][0];
    assert row.level == 4;
    assert "Admin override" in row.label;
    assert "road cut" in row.reason;
    other = [r for r in rows if r.inc_id == "INC-802"][0];
    assert other.level == 4;
    assert "override" not in other.label.lower();
    add_override(hub, "INC-801", 9, "life at risk", "District desk");
    again = [r for r in alert_board(hub) if r.inc_id == "INC-801"][0];
    assert again.level == 5;
    assert again.reason.endswith("life at risk");
}
