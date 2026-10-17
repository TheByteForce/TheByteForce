"""Volunteer centre tests: offers are matched to open needs, on private hubs."""

import from crisisconnect.store { fresh_hub }
import from crisisconnect.schema { Message, Incident, Holds }

def add_offer(hub: CrisisConnectHub, mid: str, text: str) {
    hub +>:Holds:+> Message(msg_id=mid, text=text, kind="OFFER");
}

def add_inc(hub: CrisisConnectHub, iid: str, place: str, needs: list[str], status: str, prio: float, vuln: list[str]) {
    hub +>:Holds:+> Incident(inc_id=iid, place=place, needs=needs, status=status, priority=prio, vulnerable=vuln);
}

test "offer_resources finds several resources case-insensitively" {
    r = offer_resources("We have a BOAT and a Tractor, plus dry rations and a Doctor");
    assert "boat" in r;
    assert "vehicle" in r;
    assert "food" in r;
    assert "medical" in r;
    assert "water" not in r;
    assert offer_resources("hello there") == [];
}

test "a boat offer matches an incident needing rescue" {
    hub = fresh_hub("t-vc-boat");
    add_offer(hub, "O1", "Boat available near Mawanella");
    add_inc(hub, "INC-001", "Temple Road, Mawanella", ["rescue"], "NEW", 50.0, []);
    ms = match_offers(hub);
    assert len(ms) == 1;
    assert ms[0].inc_id == "INC-001";
    assert ms[0].resource == "boat";
    assert ms[0].same_area;
    assert "same area" in ms[0].reason;
}

test "same-area incidents rank first" {
    hub = fresh_hub("t-vc-area");
    add_offer(hub, "O1", "We can offer a van in Mawanella");
    add_inc(hub, "INC-001", "Lake Road, Kegalle", ["rescue"], "NEW", 90.0, []);
    add_inc(hub, "INC-002", "Temple Road, Mawanella", ["food"], "NEW", 10.0, []);
    ms = match_offers(hub);
    assert len(ms) == 2;
    assert ms[0].inc_id == "INC-002";
    assert not ms[1].same_area;
}

test "resolved incidents are excluded" {
    hub = fresh_hub("t-vc-resolved");
    add_offer(hub, "O1", "Boat offered in Kegalle");
    add_inc(hub, "INC-001", "Kegalle", ["boat"], "RESOLVED", 80.0, []);
    assert len(match_offers(hub)) == 0;
}

test "at most three matches per offer" {
    hub = fresh_hub("t-vc-max");
    add_offer(hub, "O1", "Lorry available in Kegalle");
    for i in range(5) {
        add_inc(hub, f"INC-00{i + 1}", "Kegalle", ["food"], "NEW", 10.0 + i, []);
    }
    ms = match_offers(hub);
    assert len(ms) == 3;
    assert ms[0].inc_id == "INC-005";
}

test "an offer with no matching need gives no matches" {
    hub = fresh_hub("t-vc-none");
    add_offer(hub, "O1", "A doctor is available in Kegalle");
    add_inc(hub, "INC-001", "Kegalle", ["boat", "rescue"], "NEW", 70.0, []);
    assert len(match_offers(hub)) == 0;
}
