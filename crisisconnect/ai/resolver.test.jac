import from jaclang.byllm.lib { MockLLM }

test "resolver scorer can reject the suggested household" {
    resolver_model = MockLLM(outputs=[MatchAssessment(same_household=False, confidence=0.92, reason="Different house number")]);
    result = assess_match("House 14", "House 22", ["same surname"], "Surname alone is insufficient");
    assert not result.same_household;
    assert result.reason == "Different house number";
    assert resolver_model.exhausted();
}

test "resolver with no candidate explicitly creates a new incident" {
    msg = Message(msg_id="resolver-empty", text="Help");
    w = msg spawn Resolver();
    assert w.chosen_inc_id == "";
    assert w.model == "rules";
}
