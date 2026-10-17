"""Agent tool tests: each on a private hub built by hand."""

import from crisisconnect.store { fresh_hub }
import from crisisconnect.seed { seed_spine, seed_registry, seed_bulletins }

def mk_inc(hub: CrisisConnectHub, iid: str, status: str = "CONFIRMED") -> Incident {
    inc = Incident(
        inc_id=iid, status=status, headcount=4, needs=["boat"], vulnerable=["elderly", "child"],
        place="temple road mawanella", first_seen="18:10", last_seen="18:30"
    );
    hub +>:Holds:+> inc;
    return inc;
}

def mk_msg(hub: CrisisConnectHub, inc: Incident, mid: str, text: str, seq: int, t: str) -> Message {
    m = Message(msg_id=mid, text=text, channel="SMS", storm_time=t, seq=seq);
    hub +>:Holds:+> m;
    m +>:PartOf:+> inc;
    return m;
}

test "summary of an incident" {
    hub = fresh_hub("t-at-sum");
    inc = mk_inc(hub, "INC-001");
    mk_msg(hub, inc, "m001", "help", 1, "18:06");
    s = incident_summary_in(hub, "INC-001");
    assert "INC-001" in s;
    assert "CONFIRMED" in s;
    assert "4 people" in s;
    assert "1 messages" in s;
}

test "timeline is ordered by sequence" {
    hub = fresh_hub("t-at-tl");
    inc = mk_inc(hub, "INC-001");
    mk_msg(hub, inc, "m002", "second", 2, "18:20");
    mk_msg(hub, inc, "m001", "first", 1, "18:06");
    s = incident_timeline_in(hub, "INC-001");
    assert s.index("m001") < s.index("m002");
    assert "18:06 SMS" in s;
}

test "vulnerable flags cite the right message" {
    hub = fresh_hub("t-at-vf");
    inc = mk_inc(hub, "INC-001");
    mk_msg(hub, inc, "m001", "water rising", 1, "18:06");
    mk_msg(hub, inc, "m002", "my grandmother cannot walk", 2, "18:10");
    s = vulnerable_flags_in(hub, "INC-001");
    assert "elderly <- m002" in s;
    assert "child <- no message" in s;
}

test "waiting time uses storm time" {
    hub = fresh_hub("t-at-wt");
    mk_inc(hub, "INC-001");
    hub.storm_time = "19:40";
    s = waiting_time_in(hub, "INC-001");
    assert "1 h 30 min" in s;
}

test "verified incident finds confirmed with call log and skips unconfirmed" {
    hub = fresh_hub("t-at-vi");
    a = mk_inc(hub, "INC-001");
    b = mk_inc(hub, "INC-002", "NEW");
    m = mk_msg(hub, a, "m001", "help", 1, "18:06");
    pn = PersonName(canonical="kamal perera", display="Kamal Perera");
    hub +>:Holds:+> pn;
    m +>:Names:+> pn;
    cl = CallLog(outcome="REACHED", desk="desk1", storm_time="18:40");
    hub +>:Holds:+> cl;
    cl +>:Logged:+> a;
    s = verified_incident_for_in(hub, "Temple Road", "Kamal Perera, Nimal");
    assert "INC-001" in s;
    assert "REACHED" in s;
    assert "INC-002" not in s;
}

test "lookup official hit and miss" {
    hub = fresh_hub("t-at-lo");
    seed_registry(hub);
    # seed_registry loads crisisconnect/fixtures/registry.json (the registry the storm-night appeals use)
    hit = lookup_official_in(hub, "A. Silva", "Kegalle District Relief Unit");
    assert "07X-555-0900" in hit;
    miss = lookup_official_in(hub, "A. Silva", "Flood Heroes Foundation");
    assert "not in registry" in miss;
    assert "Hill Country" in lookup_ngo_in(hub, "hill country relief trust");
}

test "appeals sharing counts a shared account" {
    hub = fresh_hub("t-at-as");
    acct = BankAccount(account="SYN-XXXX-0001");
    hub +>:Holds:+> acct;
    for i in range(3) {
        ap = Appeal(appeal_id=f"APL-0{i}", text="donate");
        hub +>:Holds:+> ap;
        ap +>:PaysTo:+> acct;
    }
    s = appeals_sharing_in(hub, "SYN-XXXX-0001");
    assert "3 appeals" in s;
    assert "APL-02" in s;
}

test "bulletins match by area and channel resolves" {
    hub = fresh_hub("t-at-bu");
    seed_spine(hub);
    seed_registry(hub);
    seed_bulletins(hub);
    s = official_bulletins_in(hub, "kegalle");
    assert "Landslide Watch" in s;
    assert "District Flood Desk" in s;
    c = official_channel_for_in(hub, "Mawanella North");
    assert "Kegalle" in c;
    assert "Divisional Secretariat" in c;
}

test "open incidents by place text" {
    hub = fresh_hub("t-at-oi");
    mk_inc(hub, "INC-001");
    mk_inc(hub, "INC-002", "RESOLVED");
    s = open_incidents_in_in(hub, "mawanella");
    assert "INC-001" in s;
    assert "INC-002" not in s;
}

test "unknown id returns not found" {
    hub = fresh_hub("t-at-nf");
    assert "not found" in incident_summary_in(hub, "INC-999");
    assert "not found" in incident_timeline_in(hub, "INC-999");
    assert "not found" in vulnerable_flags_in(hub, "INC-999");
    assert "not found" in waiting_time_in(hub, "INC-999");
}
