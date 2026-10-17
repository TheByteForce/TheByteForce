test "R8 unverified is not a fraud signal" {
    assert referee_appeal([], False, False) == "UNVERIFIED";
    assert referee_appeal([], True, False) == "UNVERIFIED";
}
test "R8 a shared ring alone is suspicious, independent evidence is required" {
    assert referee_appeal(["shared_identifier_ring"], False, False) == "SUSPICIOUS";
    assert referee_appeal(["shared_identifier_ring", "shared_identifier_ring"], False, False) == "SUSPICIOUS";
    assert referee_appeal(["shared_identifier_ring", "requests_reader_credentials"], False, False) == "LIKELY_SCAM";
}
test "R9 matched requires both a human-confirmed need and an official channel" {
    assert referee_appeal([], True, True) == "MATCHED";
    assert referee_appeal([], False, True) == "UNVERIFIED";
    assert referee_appeal(["requests_reader_credentials"], True, True) == "SUSPICIOUS";
}
test "R10 and R11 public warnings require analyst and native review" {
    assert not warning_allowed(False, "en", True);
    assert not warning_allowed(True, "si", False);
    assert not warning_allowed(True, "ta", False);
    assert warning_allowed(True, "si", True);
    assert warning_allowed(True, "en", False);
}


import from ekata.store { fresh_hub }
import from ekata.schema { CallLog, Logged, PersonName }

test "verified need and NGO channel produce a cited matched appeal" {
    hub = fresh_hub("casework-match");
    inc = Incident(inc_id="CASE-INC", status="CONFIRMED", summary="Synthetic household needs food");
    hub +>:Holds:+> inc;
    msg = Message(msg_id="case-msg", text="Need food");
    hub +>:Holds:+> msg;
    import from ekata.schema { PartOf }
    msg +>:PartOf:+> inc;
    phone = Phone(number="07X5550901"); hub +>:Holds:+> phone;
    msg +>:HasPhone:+> phone;
    call = CallLog(outcome="REACHED_CONFIRMED", desk="Desk A"); hub +>:Holds:+> call;
    call +>:Logged:+> inc;
    ap = Appeal(appeal_id="CASE-APL", text="Donate through registered synthetic NGO"); hub +>:Holds:+> ap;
    ap +>:AppealHasPhone:+> phone;
    hub +>:Holds:+> RegistryEntry(office="Synthetic NGO", contact="07X-555-0901", kind="NGO");
    view = review_appeal(hub, ap);
    assert view.verdict == "MATCHED";
    assert "CASE-INC" in view.incident_ids;
    assert len([ap ->:ClaimsFor:->]) == 1;
    assert ap.approved_by == "";
}

test "ring plus credential request escalates, separate weak links do not make a ring" {
    hub = fresh_hub("casework-ring");
    bank = BankAccount(account="SYN-TEST-0001"); hub +>:Holds:+> bank;
    ap = Appeal(appeal_id="RING-A", text="Donate", credential_requests=["OTP"], source_msg_id="ring-src"); hub +>:Holds:+> ap;
    ap +>:PaysTo:+> bank;
    for id in ["RING-B", "RING-C"] {
        other = Appeal(appeal_id=id, text="Another appeal"); hub +>:Holds:+> other;
        other +>:PaysTo:+> bank;
    }
    assert review_appeal(hub, ap).verdict == "LIKELY_SCAM";
    assert ap.approved_by == "";
}

test "two official mismatch descriptions are not independent fraud signals" {
    assert referee_appeal(["official_contact_mismatch", "unregistered_claimed_office"], False, False) == "SUSPICIOUS";
}
