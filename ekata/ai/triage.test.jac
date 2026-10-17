import from ekata.store { fresh_hub }
import from ekata.schema { Incident, Holds }
import from ekata.views { QueueRow }

test "ranker tools are the shared agent tools when bound to a hub" {
    hub = fresh_hub("t-triage-1");
    inc = Incident(inc_id="INC-T1", status="NEW", summary="Synthetic family of four", headcount=4, vulnerable=["child"]);
    hub +>:Holds:+> inc;
    r = Ranker(rows=[QueueRow(inc_id="INC-T1", vulnerable=["child"], waiting="20 min")], hub=hub);
    s = r.incident_summary("INC-T1");
    assert "INC-T1 NEW, 4 people" in s;
    assert "vulnerable: child" in s;
    assert r.vulnerable_flags("INC-T1").startswith("INC-T1 flags: child");
}

test "ranker tools fall back to the queue rows without a hub" {
    r = Ranker(rows=[QueueRow(inc_id="INC-T2", vulnerable=["elderly"], waiting="35 min", headline="Two elderly", place="Road 1", reason="elderly")]);
    assert r.vulnerable_flags("INC-T2") == "elderly";
    assert r.waiting_time("INC-T2") == "35 min";
    assert r.vulnerable_flags("NOPE") == "none";
    assert r.incident_summary("NOPE") == "Not in the current top five";
}
