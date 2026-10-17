"""Verify real graph-guided routing and scoring with two synthetic households."""
import from ekata.ai.resolver { Resolver }
import from ekata.schema { Message, Incident, Candidate }
with entry:__main__ {
    msg = Message(msg_id="live-resolver", text="Kumari Perera, house 14 Temple Road. 3 people. Phone 07X-555-0101");
    a = Incident(inc_id="LIVE-001", summary="Kumari Perera, 3 people, phone 07X-555-0101", place="14 Temple Road");
    b = Incident(inc_id="LIVE-002", summary="Nimal Perera, phone 07X-555-0102", place="22 Temple Road");
    msg +>:Candidate(reasons=["STRONG exact phone 07X5550101 and household 14"]):+> a;
    msg +>:Candidate(reasons=["WEAK surname only; different household"]):+> b;
    result = msg spawn Resolver();
    assert result.chosen_inc_id == "LIVE-001", result.reason;
    assert result.score >= 0.5;
    assert result.model != "rules";
    print("LIVE_RESOLVER_OK " + result.reason);
}
