import from ekata.referee { r12_no_real_names }
import from ekata.schema { RefereeOutcome }

test "R12 every fixture and seeded bulletin names no real office" {
    folder = os.path.join("ekata", "fixtures");
    checked = 0;
    for name in sorted(os.listdir(folder)) {
        if not name.endswith(".json") or name == "recorded_run.json" { continue; }
        with open(os.path.join(folder, name), encoding="utf-8") as fh { text = fh.read(); }
        assert r12_no_real_names(text).outcome == RefereeOutcome.APPLIED;
        checked += 1;
    }
    assert checked >= 3;
    for b in bulletin_seeds() {
        assert r12_no_real_names(b.issuer + " " + b.text).outcome == RefereeOutcome.APPLIED;
    }
}
