"""Appeal check tests: each on a private hub, built by hand."""

import from ekata.store { fresh_hub }

def mk_appeal(hub: EkataHub, aid: str, text: str, office: str = "", contact: str = "") -> Appeal {
    ap = Appeal(appeal_id=aid, text=text);
    hub +>:Holds:+> ap;
    if office != "" {
        co = ClaimedOfficial(office=office, contact=contact);
        hub +>:Holds:+> co;
        ap +>:ClaimsToBe:+> co;
    }
    return ap;
}

def pay_to(hub: EkataHub, ap: Appeal, acct: BankAccount) {
    ap +>:PaysTo:+> acct;
}

def mk_registry(hub: EkataHub) {
    hub +>:Holds:+> RegistryEntry(office="Sri Lanka Red Cross", contact="0112222222", kind="NGO");
}

def only(vs: list[AppealVerdict], aid: str) -> AppealVerdict {
    for v in vs {
        if v.appeal_id == aid {
            return v;
        }
    }
    return vs[0];
}

test "ring of four sharing one account gives RING" {
    hub = fresh_hub("t-ac-ring");
    acct = BankAccount(account="SYN-XXXX-0001");
    hub +>:Holds:+> acct;
    for i in range(4) {
        ap = mk_appeal(hub, f"APL-0{i}", "Please donate to this account");
        pay_to(hub, ap, acct);
    }
    v = check_appeal(hub, [hub ->:Holds:->[?:Appeal, appeal_id == "APL-00"]][0]);
    assert "RING" in v.signals;
    assert v.verdict == "SUSPICIOUS";
    assert "SYN-XXXX-0001" in v.evidence[0];
}

test "an unknown office gives IMPERSONATION" {
    hub = fresh_hub("t-ac-imp");
    mk_registry(hub);
    ap = mk_appeal(hub, "APL-10", "Relief fund drive", "Flood Heroes Foundation", "0771234567");
    v = check_appeal(hub, ap);
    assert v.signals == ["IMPERSONATION"];
}

test "a registered office with a different contact gives IMPERSONATION" {
    hub = fresh_hub("t-ac-imp2");
    mk_registry(hub);
    ap = mk_appeal(hub, "APL-11", "Red Cross appeal", "Red Cross", "0779999999");
    v = check_appeal(hub, ap);
    assert "IMPERSONATION" in v.signals;
}

test "asking for NIC or OTP gives CREDENTIALS" {
    hub = fresh_hub("t-ac-cred");
    ap = mk_appeal(hub, "APL-20", "To receive aid send your NIC photo and the OTP we text you");
    v = check_appeal(hub, ap);
    assert v.signals == ["CREDENTIALS"];
    assert v.verdict == "SUSPICIOUS";
}

test "two signal types give LIKELY_SCAM" {
    hub = fresh_hub("t-ac-two");
    mk_registry(hub);
    ap = mk_appeal(hub, "APL-30", "Send your bank password to claim", "Fake Aid Org", "0771111111");
    v = check_appeal(hub, ap);
    assert v.verdict == "LIKELY_SCAM";
    assert len(v.signals) == 2;
}

test "no signals and no confirmed match is UNVERIFIED, never a scam" {
    hub = fresh_hub("t-ac-unv");
    mk_registry(hub);
    ap = mk_appeal(hub, "APL-40", "Please help Kamal Perera", "Sri Lanka Red Cross", "0112222222");
    v = check_appeal(hub, ap);
    assert v.signals == [];
    assert v.verdict == "UNVERIFIED";
}

test "confirmed incident name plus registered office is MATCHED, and apply writes" {
    hub = fresh_hub("t-ac-match");
    mk_registry(hub);
    inc = Incident(inc_id="INC-001", status="CONFIRMED");
    hub +>:Holds:+> inc;
    msg = Message(msg_id="W-001", text="help", seq=1);
    hub +>:Holds:+> msg;
    msg +>:PartOf:+> inc;
    pn = PersonName(canonical="kamal perera", display="Kamal Perera");
    hub +>:Holds:+> pn;
    msg +>:Names:+> pn;
    good = mk_appeal(hub, "APL-50", "Appeal for Kamal Perera via Red Cross", "Sri Lanka Red Cross", "0112222222");
    bad = mk_appeal(hub, "APL-51", "Send OTP now", "Nobody Org", "0770000000");
    assert good.verdict == "CHECKING";
    vs = check_all_appeals(hub, False);
    assert good.verdict == "CHECKING";
    vs = check_all_appeals(hub, True);
    assert vs[0].appeal_id == "APL-51";
    assert vs[0].verdict == "LIKELY_SCAM";
    assert vs[1].verdict == "MATCHED";
    assert good.verdict == "MATCHED";
    assert bad.verdict == "LIKELY_SCAM";
    assert good.reason != "";
}
