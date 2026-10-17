"""Intake tests: MockLLM scripted outputs, plus the regex fallback (no model)."""

import from jaclang.byllm.lib { MockLLM }

glob SOS_TEXT: str = "Please help, my grandmother Seelawathie Perera is 78 and in a wheelchair. Water is at the door of our house No. 14 Hettimulla Road, Kegalle. We cannot carry her out. Kasun 07X-555-0101";

def scripted_report(phone: str) -> ReportDraft {
    return ReportDraft(
        kind=DraftKind.SOS,
        people_count=2,
        vulnerable=["elderly", "wheelchair"],
        needs=["boat"],
        place_text="14 Hettimulla Road, Kegalle",
        place_level=DraftPlace.HOUSEHOLD,
        house_ref="14 Hettimulla Road",
        phones=[phone],
        names=[DraftName(display="Seelawathie Perera", canonical="Seelawathie  PERERA")],
        language="en",
        summary="Elderly wheelchair user at 14 Hettimulla Road needs a boat.",
        confidence=0.93
    );
}

test "intake returns the scripted report and applies the exact rules" {
    intake_model = MockLLM(outputs=[scripted_report("07X 555 0101")]);
    rep = extract_report(SOS_TEXT, "WHATSAPP");
    assert intake_model.exhausted();
    assert rep.kind == MsgKind.SOS;
    assert rep.house_ref == "14 Hettimulla Road";
    assert rep.place_level == PlaceLevel.HOUSEHOLD;
    assert rep.names[0].canonical == "seelawathie perera";
    assert rep.names[0].display == "Seelawathie Perera";
    # off-vocabulary vulnerable tags are dropped
    assert rep.vulnerable == ["elderly"];
    assert intake_run_info()["engine"] == "llm";
}

test "intake normalises phone variants to one form" {
    assert normalise_phone("07X 555 0101") == "07X5550101";
    assert normalise_phone("07X-555-0101") == "07X5550101";
    assert normalise_phone("+947X5550101") == "07X5550101";
    assert normalise_phone("+94 7X 555 0101") == "07X5550101";
    assert normalise_phone("947X5550101") == "07X5550101";
    assert normalise_phone("0094 7X 555 0101") == "07X5550101";
    assert normalise_phone("07x5550101") == "07X5550101";
    assert normalise_phone("0715550101") == "0715550101";
    assert normalise_phone("+94715550101") == "0715550101";
}

test "intake merges model phones with regex phones into one deduplicated list" {
    intake_model = MockLLM(outputs=[scripted_report("+947X5550101")]);
    rep = extract_report(SOS_TEXT, "WHATSAPP");
    assert rep.phones == ["07X5550101"];
}

test "intake demotes HOUSEHOLD to ROAD when the model gives no house reference" {
    bad = scripted_report("07X 555 0101");
    bad.house_ref = "";
    bad.place_text = "Hettimulla Road, Kegalle";
    bad.names = [];
    intake_model = MockLLM(outputs=[bad]);
    rep = extract_report(SOS_TEXT, "WEB");
    assert rep.place_level == PlaceLevel.ROAD;
}

test "intake falls back to the rules when the model call fails" {
    intake_model = MockLLM(outputs=[]);
    rep = extract_report(SOS_TEXT, "WHATSAPP");
    assert intake_run_info()["engine"] == "rules";
    assert rep.kind == MsgKind.SOS;
    assert "07X5550101" in rep.phones;
}

test "intake prompt carries the sem notes" {
    intake_model = MockLLM(outputs=[scripted_report("07X 555 0101")]);
    extract_report(SOS_TEXT, "WEB");
    sent = str(intake_model.sent("messages"));
    assert "house number" in sent;
    assert "Lowercase romanised" in sent;
    assert "FROM THE READER" in sent;
}

test "rules: an SOS with a wheelchair is elderly" {
    rep = extract_report_rules(SOS_TEXT, "WHATSAPP");
    assert rep.kind == MsgKind.SOS;
    assert "elderly" in rep.vulnerable;
    assert rep.place_level == PlaceLevel.HOUSEHOLD;
    assert rep.house_ref == "14 Hettimulla Road";
    assert rep.phones == ["07X5550101"];
    assert rep.language == "en";
}

test "rules: a baby and asthma are child and medical, a 6 year old child is not elderly" {
    rep = extract_report_rules(
        "Water entering houses near Rambukkana town. Kumari Jayasinghe, 3 of us, my daughter (6) has high fever and asthma, inhaler finished. 07X-555-0107",
        "SMS"
    );
    assert "child" in rep.vulnerable;
    assert "medical" in rep.vulnerable;
    assert "elderly" not in rep.vulnerable;
    assert rep.people_count == 3;
    assert rep.names[0].canonical == "kumari jayasinghe";
}

test "rules: already rescued is an UPDATE with rescued set" {
    rep = extract_report_rules("Update: Seelawathie Perera was already rescued by the navy boat, we are safe now at the Kegalle camp. 07X-555-0102", "SMS");
    assert rep.kind == MsgKind.UPDATE;
    assert rep.rescued;
}

test "rules: not safe is still an SOS" {
    rep = extract_report_rules("We are not safe, water at the door, 4 people on the roof, 07X-555-0103", "SMS");
    assert rep.kind == MsgKind.SOS;
    assert not rep.rescued;
    assert rep.people_count == 4;
}

test "rules: a deposit and NIC text is an APPEAL that asks for credentials" {
    rep = extract_report_rules(
        "Flood victims in Rambukkana need funds. Deposit to account SYN-7781-0042 and send your NIC photo and the OTP you receive to verify. Call 07X-555-0170 or see https://flood-help.example/donate",
        "WHATSAPP"
    );
    assert rep.kind == MsgKind.APPEAL;
    assert "NIC photo" in rep.asks_credentials;
    assert "OTP" in rep.asks_credentials;
    assert rep.payee_accounts == ["SYN-7781-0042"];
    assert rep.urls == ["https://flood-help.example/donate"];
    assert rep.phones == ["07X5550170"];
}

test "rules: a Kotmale dam breached text is a RUMOUR" {
    rep = extract_report_rules("URGENT!!! Kotmale dam has breached, everyone in Kegalle move to high ground NOW. Share!!!", "WHATSAPP");
    assert rep.kind == MsgKind.RUMOUR;
    assert not rep.rescued;
}

test "rules: a boat offer is an OFFER" {
    rep = extract_report_rules("Boat available at Mawanella bridge, can help 6 people. Call 07X-555-0190", "WEB");
    assert rep.kind == MsgKind.OFFER;
}

test "rules: Singlish and Tamil script are detected" {
    s = extract_report_rules("Galigamuwa, Ranjith Silva. Api dennama wayasai, gedara wathura pirila. Udaw karanna. 07X-555-0110", "SMS");
    assert s.language == "singlish";
    t = extract_report_rules("தயவு செய்து உதவுங்கள். வெள்ளம் வீட்டுக்குள். 07X-555-0108", "SMS");
    assert t.language == "ta";
    n = extract_report_rules("කරුණාකර උදව් කරන්න. 07X-555-0116", "SMS");
    assert n.language == "si";
}

test "rules: line house and a landmark are household places" {
    a = extract_report_rules("Line house 3 Deraniyagala estate, 5 people, water inside. 07X-555-0108", "SMS");
    assert a.place_level == PlaceLevel.HOUSEHOLD;
    assert a.house_ref.startswith("line house 3");
    b = extract_report_rules("Bandara family on Udagama Road Mawanella, house near the Bodhi temple. 6 of us. 07X-555-0104", "WEB");
    assert b.place_level == PlaceLevel.HOUSEHOLD;
    assert b.house_ref == "near the Bodhi temple";
    c = extract_report_rules("Water rising on Udagama Road, 4 of us. 07X-555-0104", "WEB");
    assert c.place_level == PlaceLevel.ROAD;
}
