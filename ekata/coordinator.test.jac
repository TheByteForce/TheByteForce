"""Coordinator tests: the rules-only path (EKATA_AI=off), each on a private hub."""

import from ekata.store { fresh_hub }
import from ekata.seed { reset_and_seed }
import from ekata.fixtures { prepare_replay }

def rules_hub(name: str) -> EkataHub {
    os.environ["EKATA_AI"] = "off";
    hub = fresh_hub(name);
    ensure_seeded(hub);
    return hub;
}

test "same phone twice gives one incident" {
    hub = rules_hub("t-phone");
    a = process_in_hub(hub, "Help please, water is rising. 4 people at No 5 Temple Road, Mawanella. Call 07X-555-0201", "SMS", "18:10", "t1a");
    b = process_in_hub(hub, "Still waiting for the boat, 4 people on the roof. 07X-555-0201", "SMS", "18:25", "t1b");
    assert len(all_incidents(hub)) == 1;
    inc = all_incidents(hub)[0];
    assert len(messages_of(inc)) == 2;
    assert a.kind == "SOS";
    assert b.kind == "SOS";
    assert inc.headcount == 4;
}

test "same surname on the same road is never auto-merged" {
    hub = rules_hub("t-surname");
    process_in_hub(hub, "Sunil Bandara, No 7 Udagama Road, Mawanella. 4 people on the roof. Water rising fast. 07X-555-0103", "WHATSAPP", "18:14", "t2a");
    process_in_hub(hub, "Kamala Bandara, Udagama Road near the Bodhi temple, 3 people stuck upstairs. 07X-555-0104", "WHATSAPP", "18:40", "t2b");
    assert len(all_incidents(hub)) == 2;
    for inc in all_incidents(hub) {
        assert len(messages_of(inc)) == 1;
    }
    assert len(all_proposals(hub)) == 0;
}

test "an already-rescued update only proposes closing" {
    hub = rules_hub("t-rescued");
    process_in_hub(hub, "Kumari Perera, 5 people at No 9 Lake Road, Kegalle. Water on the first floor. 07X-555-0301", "SMS", "18:30", "t3a");
    u = process_in_hub(hub, "Update: we have already been rescued, thank you. 07X-555-0301", "SMS", "19:05", "t3b");
    assert u.kind == "UPDATE";
    assert len(all_incidents(hub)) == 1;
    inc = all_incidents(hub)[0];
    assert inc.status == "CLOSE_PROPOSED";
    assert inc.status != "RESOLVED";
}

test "a partial match goes to a person and the desk can approve it" {
    hub = rules_hub("t-approve");
    process_in_hub(hub, "Priya Wijesinghe, 3 people near Kandy Road, Kegalle. Water in the house.", "WEB", "18:20", "t4a");
    process_in_hub(hub, "Priya Wijesinghe here again, 2 people stuck at the school in Mawanella. 07X-555-0401", "WEB", "18:50", "t4b");
    assert len(all_incidents(hub)) == 2;
    props = all_proposals(hub);
    assert len(props) == 1;
    assert props[0].status == "PENDING";
    assert props[0].inc_id == "INC-001";
    res = apply_merge_decision(hub, "t4b", "INC-001", True, "desk-1");
    assert res is not None;
    assert len(all_incidents(hub)) == 1;
    assert len(messages_of(all_incidents(hub)[0])) == 2;
    assert all_proposals(hub)[0].status == "APPROVED";
}

test "the desk can reject a proposed merge" {
    hub = rules_hub("t-reject");
    process_in_hub(hub, "Priya Wijesinghe, 3 people near Kandy Road, Kegalle. Water in the house.", "WEB", "18:20", "t5a");
    process_in_hub(hub, "Priya Wijesinghe here again, 2 people stuck at the school in Mawanella. 07X-555-0401", "WEB", "18:50", "t5b");
    apply_merge_decision(hub, "t5b", "INC-001", False, "desk-1");
    assert len(all_incidents(hub)) == 2;
    assert all_proposals(hub)[0].status == "REJECTED";
}

test "a logged call resolves; a second desk cannot take a claimed incident" {
    hub = rules_hub("t-calls");
    process_in_hub(hub, "Nimal Silva, 3 people at No 2 Hill Lane, Kegalle. Need a boat. 07X-555-0601", "HOTLINE", "18:10", "t6a");
    inc = all_incidents(hub)[0];
    assert inc.status == "NEW";
    record_call(hub, inc.inc_id, "REACHED_CONFIRMED", "desk-1", "spoke to Nimal");
    assert inc.status == "CONFIRMED";
    assert inc.claimed_by == "desk-1";
    record_call(hub, inc.inc_id, "STILL_IN_NEED", "desk-2", "");
    assert inc.claimed_by == "desk-1";
    assert len([inc <-:Logged:<-[?:CallLog]]) == 1;
    record_call(hub, inc.inc_id, "RESCUED", "desk-1", "boat arrived");
    assert inc.status == "RESOLVED";
    assert len(build_queue(hub)) == 0;
}

test "appeals, rumours and offers never become incidents" {
    hub = rules_hub("t-other");
    process_in_hub(hub, "Donate to the Kegalle flood fund, account 1234567890, Bank of Ceylon. Call 07X-555-0501", "WHATSAPP", "19:00", "t7a");
    process_in_hub(hub, "URGENT!!! Kotmale dam has breached, everyone in Kegalle move to high ground NOW. Share!!!", "WHATSAPP", "19:02", "t7b");
    process_in_hub(hub, "We can offer a tractor and two volunteers near Mawanella. 07X-555-0502", "SMS", "19:05", "t7c");
    assert len(all_incidents(hub)) == 0;
    assert len([hub ->:Holds:->[?:Appeal]]) == 1;
    assert len([hub ->:Holds:->[?:RumourClaim]]) == 1;
    assert len(all_messages(hub)) == 3;
}

test "every pipeline step is recorded as a decision" {
    hub = rules_hub("t-trace");
    process_in_hub(hub, "My grandmother Seelawathie Perera is 78 and in a wheelchair, house No 14 Hettimulla Road, Kegalle. 07X-555-0101", "WHATSAPP", "18:06", "t8a");
    rows = decisions_since(hub, 0, 50);
    agents = [r.agent for r in rows];
    assert "intake" in agents;
    assert "blocking" in agents;
    assert "freshness" in agents;
    assert "priority" in agents;
    inc = all_incidents(hub)[0];
    view = build_incident_view(hub, inc);
    assert len(view.trace) >= 4;
    assert "elderly" in view.vulnerable;
    assert "disability" in view.vulnerable;
}

test "replay five messages on the shared hub gives a non-empty queue" {
    os.environ["EKATA_AI"] = "off";
    hub = get_hub();
    reset_and_seed(hub);
    assert prepare_replay(hub) > 0;
    last = replay_in_hub(hub, 1);
    for i in range(4) {
        last = replay_in_hub(hub, 1);
    }
    assert last.position == 5;
    assert not last.locked;
    assert len(last.queue) > 0;
    assert last.message is not None;
    assert len(last.new_trace) > 0;
    assert len(decisions_since(hub, 0, 50)) > 10;
    assert build_metrics(hub).messages == 5;
}
