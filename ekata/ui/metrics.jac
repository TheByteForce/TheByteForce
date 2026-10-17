"""Results: operational counters kept apart from measured evaluation results."""
import from "react" { useEffect }
import type from ekata.views { Metrics }
import type from ekata.evaluation { EvaluationReport }
import from ekata.api { metrics }
import from ekata.evaluation_api { evaluation_results }
import from .atoms { Empty }

def:pub Stat(label: str, value: str, detail: str = "") -> JsxElement {
    <div className="min-w-0 border-l-2 border-primary pl-3">
        <p className="text-[13px] text-muted-foreground">{label}</p>
        <p className="text-[21px] font-semibold leading-tight">{value}</p>
        {if detail != "" {
            <p className="mt-0.5 text-[13px] text-muted-foreground">{detail}</p>
        }}
    </div>
}

def:pub MetricsPage -> JsxElement {
    has live: Metrics | None = None;
    has scores: EvaluationReport | None = None;
    has tick: int = 0;
    has error: str = "";
    async def refresh -> None {
        try {
            tick = tick + 1;
            live = await metrics(tick);
            scores = await evaluation_results(tick);
            error = "";
        } except Exception as e {
            error = "Could not load results: " + str(e);
        }
    }
    async can with entry {
        await refresh();
    }
    useEffect(
        lambda {
            timer = setInterval(lambda { refresh(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        []
    );
    <section aria-label="Results" className="space-y-8">
        {if error != "" {
            <p
                role="alert"
                className="rounded-md border border-blocked/30 bg-blocked-soft p-3 text-[15px] text-blocked"
            >
                {error}
            </p>
        }}
        <div>
            <h2 className="text-[17px] font-semibold">Current desk</h2>
            <p className="mb-3 text-[13px] text-muted-foreground">
                Counts for this night so far. These are not accuracy scores.
            </p>
            {if live is not None {
                <div className="grid gap-4 sm:grid-cols-3">
                    <Stat label="Messages received" value={str(live.messages)}/>
                    <Stat label="Rescue cases" value={str(live.incidents)}/>
                    <Stat
                        label="Calls saved by merging"
                        value={str(live.calls_saved)}
                        detail="Rescue messages minus distinct cases"
                    />
                </div>
            }}
        </div>
        {if scores is None {
            <Empty
                title="No evaluation published yet"
                hint="Results appear after a labelled evaluation has run. No accuracy is assumed."
            />
        }}
        {if scores is not None {
            <div className="space-y-8">
                <div>
                    <h2 className="text-[17px] font-semibold">Evaluation</h2>
                    <p className="mb-3 text-[13px] text-muted-foreground">
                        {scores.dataset_role + ", " + scores.mode + " mode. "
                            + scores.dataset + ", " + str(scores.messages) + " messages, "
                            + scores.generated_at}
                    </p>
                    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                        <Stat
                            label="Merge precision"
                            value={f"{scores.merge_precision * 100:.1f}%" if scores.predicted_pairs > 0 else "Not defined"}
                            detail={str(scores.correct_pairs) + " correct of " + str(scores.predicted_pairs) + " predicted pairs"}
                        />
                        <Stat
                            label="Merge recall"
                            value={f"{scores.merge_recall * 100:.1f}%" if scores.true_pairs > 0 else "Not defined"}
                            detail={str(scores.correct_pairs) + " found of " + str(scores.true_pairs) + " true pairs"}
                        />
                        <Stat
                            label="Calls saved by merging"
                            value={str(scores.calls_saved)}
                            detail={str(scores.rescue_messages) + " rescue messages became " + str(scores.incidents) + " cases"}
                        />
                        <Stat
                            label="Median processing time"
                            value={f"{scores.median_latency_ms:.0f} ms"}
                            detail={scores.mode + " engine"}
                        />
                    </div>
                    <div className="mt-5 grid gap-4 sm:grid-cols-3">
                        <Stat
                            label="Agent invocations"
                            value={str(scores.agent_calls)}
                            detail={str(scores.tokens) + " recorded tokens"}
                        />
                        <Stat
                            label="Model cost estimate"
                            value={f"${scores.cost_usd:.4f}" if scores.cost_available else ("No model calls" if scores.agent_calls == 0 else "Unavailable")}
                        />
                        <Stat
                            label="Referee interventions"
                            value={str(scores.interventions)}
                            detail={str(scores.retries) + " retries, " + str(scores.failed_messages) + " processing failures"}
                        />
                    </div>
                </div>
                <div>
                    <h2 className="mb-2 text-[17px] font-semibold">By language</h2>
                    <div className="overflow-x-auto border-y border-border">
                        <table className="w-full text-left text-[15px]">
                            <thead>
                                <tr className="border-b border-border text-[13px] text-muted-foreground">
                                    <th className="py-2 pr-4 font-semibold">Language</th>
                                    <th className="py-2 pr-4 font-semibold">Rescue messages</th>
                                    <th className="py-2 pr-4 font-semibold">Precision</th>
                                    <th className="py-2 pr-4 font-semibold">Recall</th>
                                    <th className="py-2 font-semibold">Correct and true pairs</th>
                                </tr>
                            </thead>
                            <tbody>
                                {for row in scores.languages {
                                    <tr key={row.language} className="border-b border-border last:border-0">
                                        <td className="py-2 pr-4 font-semibold">{row.language}</td>
                                        <td className="py-2 pr-4">{row.messages}</td>
                                        <td className="py-2 pr-4">
                                            {f"{row.precision * 100:.1f}%" if row.predicted_pairs > 0 else "None"}
                                        </td>
                                        <td className="py-2 pr-4">
                                            {f"{row.recall * 100:.1f}%" if row.true_pairs > 0 else "None"}
                                        </td>
                                        <td className="py-2">
                                            {str(row.correct_pairs) + " of " + str(row.true_pairs)}
                                        </td>
                                    </tr>
                                }}
                            </tbody>
                        </table>
                    </div>
                </div>
                {if len(scores.critical) > 0 {
                    <div>
                        <h2 className="mb-2 text-[17px] font-semibold">Flagged cases in the call queue</h2>
                        <ul className="divide-y divide-border border-y border-border text-[15px]">
                            {for row in scores.critical {
                                <li key={row.inc_id} className="py-2">
                                    <span className="font-semibold">{f"Rank {row.rank}, " + row.inc_id}</span>
                                    <span className="text-muted-foreground">{": " + ", ".join(row.flags)}</span>
                                </li>
                            }}
                        </ul>
                    </div>
                }}
                <div>
                    <h2 className="mb-2 text-[17px] font-semibold">What these numbers mean</h2>
                    <ul className="list-disc space-y-1.5 pl-5 text-[13px] text-muted-foreground">
                        {for note in scores.notes {
                            <li key={note}>{note}</li>
                        }}
                    </ul>
                    <p className="mt-3 text-[15px]">
                        {f"Appeal verdict accuracy: {scores.appeal_accuracy * 100:.1f}%" if scores.appeal_labels > 0 else "Appeal verdict accuracy is unavailable without verdict labels."}
                    </p>
                </div>
            </div>
        }}
    </section>
}
