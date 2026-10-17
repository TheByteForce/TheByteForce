"""GN register tests: seeding, linking by a registered phone, and the officer's order."""

import os;
import from crisisconnect.store { fresh_hub, next_msg_id }
import from crisisconnect.seed { reset_and_seed }
import from crisisconnect.coordinator { process_in_hub }

def mk_world(name: str) -> CrisisConnectHub {
    os.environ["CRISISCONNECT_AI"] = "off";
    hub = fresh_hub(name);
    reset_and_seed(hub);
    return hub;
}

def mk_register() -> RegisterHub {
    reg = RegisterHub(name="t-gn-register");
    seed_register(reg);
    return reg;
}

def say(hub: CrisisConnectHub, text: str, t: str) -> Message {
    hub.storm_time = t;
    return process_in_hub(hub, text, "SMS", t, next_msg_id(hub));
}

def row_of(view: GnRegisterView, hh_id: str) -> HouseholdRow {
    for r in view.rows {
        if r.hh_id == hh_id {
            return r;
        }
    }
    raise ValueError(f"no household {hh_id}");
}

test "the register seeds three GN divisions from the fixture" {
    reg = mk_register();
    assert reg.version == REGISTER_VERSION;
    assert register_size(reg) == 15;
    names = [c.gn for c in gn_choices_in(reg)];
    assert len(names) == 3;
    assert "Hettimulla" in names;
}

test "before any message nobody is heard and vulnerable households come first" {
    hub = mk_world("t-gn-quiet");
    view = gn_register_in(hub, mk_register(), "hettimulla");
    assert view.households == 5;
    assert view.heard == 0;
    assert view.rows[0].group == 0;
    assert view.check_now == len([r for r in view.rows if len(r.vulnerable) > 0 or r.evac_help]);
}

test "a registered phone in an SOS marks the household heard" {
    hub = mk_world("t-gn-phone");
    say(hub, "Help, water is inside the house, 4 of us with two small children. Call 07X-555-0137", "18:20");
    view = gn_register_in(hub, mk_register(), "Hettimulla");
    row = row_of(view, "HET-02");
    assert row.heard;
    assert len(row.inc_ids) == 1;
    assert row.group != 0;
    assert view.heard == 1;
}

test "a shared surname alone never links a household" {
    hub = mk_world("t-gn-surname");
    say(hub, "Help! Kamal Perera here, 3 people at 40 Kandy Road Mawanella, water rising fast. Call 07X-555-0177", "18:15");
    view = gn_register_in(hub, mk_register(), "Hettimulla");
    assert not row_of(view, "HET-01").heard;
    assert view.heard == 0;
}

test "opening a known GN is logged, an unknown one is refused" {
    hub = mk_world("t-gn-open");
    reg = mk_register();
    assert log_register_open(hub, reg, "Udagama", "");
    assert not log_register_open(hub, reg, "Nowhere", "");
    assert gn_register_in(hub, reg, "Nowhere").households == 0;
    assert gn_register_in(hub, None, "Udagama").note != "";
}
