"""Evaluate frozen predictions. Ground-truth labels are read only AFTER inference."""
import os;
import json;
import time;
import uuid;
import re;
import statistics;
import from ekata.fixtures { parse_fixture }
import from ekata.store { fresh_hub, wipe_hub, all_messages, all_incidents, incident_of, messages_of }
import from ekata.seed { ensure_seeded }
import from ekata.coordinator { process_in_hub, build_queue }
import from ekata.schema { Holds, Appeal, Decision }
import from ekata.ai.models { call_stats }

obj LanguageScore {
    has language: str;
    has messages: int = 0;
    has correct_pairs: int = 0;
    has predicted_pairs: int = 0;
    has true_pairs: int = 0;
    has precision: float = 0.0;
    has recall: float = 0.0;
}
obj CriticalRank {
    has inc_id: str;
    has rank: int;
    has flags: list[str] = [];
}
obj EvaluationReport {
    has dataset: str = "";
    has dataset_role: str = "development fixture";
    has mode: str = "rules";
    has generated_at: str = "";
    has messages: int = 0;
    has rescue_messages: int = 0;
    has incidents: int = 0;
    has calls_saved: int = 0;
    has correct_pairs: int = 0;
    has predicted_pairs: int = 0;
    has true_pairs: int = 0;
    has merge_precision: float = 0.0;
    has merge_recall: float = 0.0;
    has kind_accuracy: float = 0.0;
    has appeal_accuracy: float = 0.0;
    has appeal_labels: int = 0;
    has median_latency_ms: float = 0.0;
    has agent_calls: int = 0;
    has tokens: int = 0;
    has cost_usd: float = 0.0;
    has cost_available: bool = False;
    has interventions: int = 0;
    has retries: int = 0;
    has failed_messages: int = 0;
    has languages: list[LanguageScore] = [];
    has critical: list[CriticalRank] = [];
    has notes: list[str] = [];
}

def pair_counts(ids: list[str], truth: dict[str, str], predicted: dict[str, str]) -> tuple[int, int, int] {
    correct = 0; guessed = 0; actual = 0;
    for i in range(len(ids)) {
        for j in range(i + 1, len(ids)) {
            a = ids[i]; b = ids[j];
            same_truth = truth[a] == truth[b];
            same_prediction = predicted.get(a, "unassigned:" + a) == predicted.get(b, "unassigned:" + b);
            if same_truth { actual += 1; }
            if same_prediction { guessed += 1; }
            if same_truth and same_prediction { correct += 1; }
        }
    }
    return (correct, guessed, actual);
}

def ratio(n: int, d: int) -> float {
    return float(n) / float(d) if d > 0 else 0.0;
}

def report_dict(r: EvaluationReport) -> dict[str, any] {
    return {
        "dataset": r.dataset, "dataset_role": r.dataset_role, "mode": r.mode, "generated_at": r.generated_at,
        "messages": r.messages, "rescue_messages": r.rescue_messages, "incidents": r.incidents, "calls_saved": r.calls_saved,
        "correct_pairs": r.correct_pairs, "predicted_pairs": r.predicted_pairs, "true_pairs": r.true_pairs,
        "merge_precision": r.merge_precision, "merge_recall": r.merge_recall, "kind_accuracy": r.kind_accuracy,
        "appeal_accuracy": r.appeal_accuracy, "appeal_labels": r.appeal_labels, "median_latency_ms": r.median_latency_ms,
        "agent_calls": r.agent_calls, "tokens": r.tokens, "cost_usd": r.cost_usd, "cost_available": r.cost_available,
        "interventions": r.interventions, "retries": r.retries, "failed_messages": r.failed_messages,
        "languages": [{"language": x.language, "messages": x.messages, "correct_pairs": x.correct_pairs, "predicted_pairs": x.predicted_pairs, "true_pairs": x.true_pairs, "precision": x.precision, "recall": x.recall} for x in r.languages],
        "critical": [{"inc_id": x.inc_id, "rank": x.rank, "flags": x.flags} for x in r.critical], "notes": r.notes
    };
}

def parse_report(d: any) -> EvaluationReport {
    r = EvaluationReport(
        dataset=str(d.get("dataset", "")), dataset_role=str(d.get("dataset_role", "development fixture")), mode=str(d.get("mode", "rules")), generated_at=str(d.get("generated_at", "")),
        messages=int(d.get("messages", 0)), rescue_messages=int(d.get("rescue_messages", 0)), incidents=int(d.get("incidents", 0)), calls_saved=int(d.get("calls_saved", 0)),
        correct_pairs=int(d.get("correct_pairs", 0)), predicted_pairs=int(d.get("predicted_pairs", 0)), true_pairs=int(d.get("true_pairs", 0)),
        merge_precision=float(d.get("merge_precision", 0)), merge_recall=float(d.get("merge_recall", 0)), kind_accuracy=float(d.get("kind_accuracy", 0)),
        appeal_accuracy=float(d.get("appeal_accuracy", 0)), appeal_labels=int(d.get("appeal_labels", 0)), median_latency_ms=float(d.get("median_latency_ms", 0)),
        agent_calls=int(d.get("agent_calls", 0)), tokens=int(d.get("tokens", 0)), cost_usd=float(d.get("cost_usd", 0)), cost_available=bool(d.get("cost_available", False)),
        interventions=int(d.get("interventions", 0)), retries=int(d.get("retries", 0)), failed_messages=int(d.get("failed_messages", 0)), notes=[str(n) for n in d.get("notes", [])]
    );
    r.languages = [LanguageScore(language=str(x["language"]), messages=int(x["messages"]), correct_pairs=int(x["correct_pairs"]), predicted_pairs=int(x["predicted_pairs"]), true_pairs=int(x["true_pairs"]), precision=float(x["precision"]), recall=float(x["recall"])) for x in d.get("languages", [])];
    r.critical = [CriticalRank(inc_id=str(x["inc_id"]), rank=int(x["rank"]), flags=[str(f) for f in x["flags"]]) for x in d.get("critical", [])];
    return r;
}

def latest_report() -> EvaluationReport | None {
    path = os.path.join(".jac", "evaluation", "latest.json");
    if not os.path.exists(path) { path = os.path.join("results", "development-rules.json"); }
    if not os.path.exists(path) { return None; }
    with open(path, encoding="utf-8") as fh { return parse_report(json.load(fh)); }
}

def evaluate_fixture(messages_path: str, labels_path: str, mode: str = "rules", dataset_role: str = "development fixture") -> EvaluationReport {
    if mode not in ["rules", "live", "cached"] { raise ValueError("Use rules, live or cached mode."); }
    if not os.path.isfile(messages_path) or not os.path.isfile(labels_path) { raise ValueError("Both message and label files must exist."); }
    old = os.environ.get("EKATA_AI", "on");
    old_cache = os.environ.get("EKATA_CACHE_MODE", "live");
    if mode == "cached" { os.environ["EKATA_CACHE_MODE"] = "cached"; }
    os.environ["EKATA_AI"] = "off" if mode == "rules" else "on";
    hub = fresh_hub("eval-" + str(uuid.uuid4()));
    ensure_seeded(hub);
    latencies: list[float] = [];
    failures = 0;
    before = call_stats();
    try {
        # The prediction phase receives only raw messages. Never load labels here.
        with open(messages_path, encoding="utf-8") as fh { inputs = parse_fixture(fh.read()); }
        if len(inputs) == 0 { raise ValueError("No valid messages in the evaluation file."); }
        input_ids = [x.msg_id for x in inputs];
        if len(set(input_ids)) != len(input_ids) { raise ValueError("Evaluation message IDs must be unique."); }
        for item in inputs {
            started = time.perf_counter();
            try { process_in_hub(hub, item.text, item.channel, item.storm_time, item.msg_id); }
            except Exception { failures += 1; }
            latencies.append((time.perf_counter() - started) * 1000.0);
        }
        predicted: dict[str, str] = {};
        kinds: dict[str, str] = {};
        languages: dict[str, str] = {};
        for msg in all_messages(hub) {
            inc = incident_of(msg);
            if inc is not None { predicted[msg.msg_id] = inc.inc_id; }
            kinds[msg.msg_id] = msg.kind;
            languages[msg.msg_id] = msg.language or "unknown";
        }
        # Freeze assignments before opening the truth file.
        with open(labels_path, encoding="utf-8") as fh { label_data: any = json.load(fh); }
        labels: any = label_data.get("messages", label_data);
        if set(labels.keys()) != set(input_ids) { raise ValueError("Label IDs must exactly match the message file."); }
        ids: list[str] = [];
        truth: dict[str, str] = {};
        correct_kind = 0;
        expected_appeals: dict[str, str] = {};
        for mid in labels.keys() {
            label_row: any = labels[mid];
            if kinds.get(mid, "") == str(label_row.get("kind", "")) { correct_kind += 1; }
            if str(label_row.get("kind", "")) in ["SOS", "UPDATE"] and label_row.get("incident") is not None {
                ids.append(str(mid)); truth[str(mid)] = str(label_row["incident"]);
            }
            if label_row.get("language") { languages[str(mid)] = str(label_row["language"]); }
            if label_row.get("verdict") { expected_appeals[str(mid)] = str(label_row["verdict"]); }
        }
        (tp, pp, actual) = pair_counts(ids, truth, predicted);
        predicted_incidents = len(set([predicted.get(mid, "unassigned:" + mid) for mid in ids]));
        after = call_stats();
        outcome = EvaluationReport(
            dataset=os.path.basename(messages_path), dataset_role=dataset_role, mode=mode,
            generated_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), messages=len(labels), rescue_messages=len(ids), incidents=predicted_incidents,
            calls_saved=max(0, len(ids) - predicted_incidents), correct_pairs=tp, predicted_pairs=pp, true_pairs=actual,
            merge_precision=ratio(tp, pp), merge_recall=ratio(tp, actual), kind_accuracy=ratio(correct_kind, len(labels)),
            median_latency_ms=statistics.median(latencies) if len(latencies) > 0 else 0.0,
            agent_calls=int(after["calls"]) - int(before["calls"]), tokens=int(after["tokens"]) - int(before["tokens"]),
            cost_usd=float(after["cost_usd"]) - float(before["cost_usd"]), cost_available=bool(after["cost_available"]), failed_messages=failures
        );
        for lang in sorted(set([languages.get(mid, "unknown") for mid in ids])) {
            subset = [mid for mid in ids if languages.get(mid, "unknown") == lang];
            (ltp, lpp, la) = pair_counts(subset, truth, predicted);
            outcome.languages.append(LanguageScore(language=lang, messages=len(subset), correct_pairs=ltp, predicted_pairs=lpp, true_pairs=la, precision=ratio(ltp, lpp), recall=ratio(ltp, la)));
        }
        for rank_row in build_queue(hub) {
            if len([x for x in rank_row.vulnerable if x in ["medical", "child", "elderly", "disability"]]) > 0 {
                outcome.critical.append(CriticalRank(inc_id=rank_row.inc_id, rank=rank_row.rank, flags=rank_row.vulnerable));
            }
        }
        decisions = [hub ->:Holds:->[?:Decision]];
        outcome.interventions = len([d for d in decisions if d.outcome in ["BLOCKED", "NEEDS_HUMAN"]]);
        outcome.retries = len([d for d in decisions if "retry" in d.action]);
        correct_appeals = 0;
        for ap in [hub ->:Holds:->[?:Appeal]] {
            if ap.source_msg_id in expected_appeals and ap.verdict == expected_appeals[ap.source_msg_id] { correct_appeals += 1; }
        }
        outcome.appeal_labels = len(expected_appeals);
        outcome.appeal_accuracy = ratio(correct_appeals, outcome.appeal_labels);
        outcome.notes = ["Results apply only to this labelled dataset.", "Language groups use provided labels where available, otherwise intake-detected language.", "Critical ranks refer to flagged incidents, not a measured clinical accuracy.", "Language pair scores use within-language pairs; mixed-language pairs are included in overall scores."];
        if dataset_role != "independent held-out" { outcome.notes.append("Development fixture results; do not describe them as independent held-out performance."); }
        if outcome.appeal_labels == 0 { outcome.notes.append("No expected appeal verdict labels supplied; appeal accuracy is unavailable."); }
        return outcome;
    } finally {
        os.environ["EKATA_AI"] = old;
        os.environ["EKATA_CACHE_MODE"] = old_cache;
        wipe_hub(hub); del hub;
}
}
