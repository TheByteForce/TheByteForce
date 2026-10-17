test "pairwise metrics penalize a wrong merge and a missed merge" {
    ids = ["a", "b", "c", "d"];
    truth = {"a": "family1", "b": "family1", "c": "family2", "d": "family2"};
    prediction = {"a": "x", "b": "x", "c": "x", "d": "y"};
    (tp, predicted, actual) = pair_counts(ids, truth, prediction);
    assert tp == 1;
    assert predicted == 3;
    assert actual == 2;
    assert ratio(tp, actual) == 0.5;
}
test "unassigned messages are separate, never silently merged" {
    (tp, predicted, actual) = pair_counts(["a", "b"], {"a": "same", "b": "same"}, {});
    assert tp == 0 and predicted == 0 and actual == 1;
}
test "saved evaluation round trips without inventing unavailable metrics" {
    original = EvaluationReport(dataset="qa", appeal_labels=0, notes=["unavailable"]);
    restored = parse_report(report_dict(original));
    assert restored.dataset == "qa";
    assert restored.appeal_labels == 0;
    assert not restored.cost_available;
}
