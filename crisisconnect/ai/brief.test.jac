import from jaclang.byllm.lib { MockLLM }

test "brief uses exactly three model questions and keeps contradictions separate" {
    brief_model = MockLLM(outputs=[CallBrief(known=["3 people"], contradictions=["headcount 3 vs 6"], questions=["Where are you?", "How many are there?", "Are you rescued?"])]);
    result = compose_brief(["3 people"], ["m1: need help"], ["headcount 3 vs 6"]);
    assert len(result.questions) == 3;
    assert "headcount 3 vs 6" in result.contradictions;
    assert brief_model.exhausted();
}
