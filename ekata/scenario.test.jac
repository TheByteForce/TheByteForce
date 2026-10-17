import os;
import from ekata.store { fresh_hub, all_incidents, messages_of }
import from ekata.portal { citizen_status, requests_of }
import from ekata.schema { Appeal }
import from ekata.timeline { build_timeline }

test "complete seven-step verified household story" {
    os.environ["EKATA_AI"] = "off";
    hub = fresh_hub("scenario-regression");
    scenario_reset_in(hub);
    first = scenario_next_in(hub);
    assert first.step == 1;
    assert len(all_incidents(hub)) == 1;
    assert len(messages_of(all_incidents(hub)[0])) == 2;
    scenario_next_in(hub);
    assert len(all_incidents(hub)) == 2;
    scenario_next_in(hub);
    assert citizen_status(hub, first.ref).stage == 2;
    scenario_next_in(hub);
    st = state_of(hub);
    req = find_request(hub, st.req_id);
    assert req is not None;
    assert req.ngo != st.first_group;
    scenario_next_in(hub);
    assert "way" in citizen_status(hub, first.ref).stage_label.lower();
    scenario_next_in(hub);
    verdicts = [x.verdict for x in [hub ->:Holds:->[?:Appeal]]];
    assert "MATCHED" in verdicts;
    assert "LIKELY_SCAM" in verdicts;
    assert scenario_next_in(hub).done;
    assert citizen_status(hub, first.ref).stage == 5;
    assert build_timeline(hub, first.inc_id).verified;
}
