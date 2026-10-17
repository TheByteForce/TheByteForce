"""Separate operational counters from measured evaluation results."""
import type from ekata.views { Metrics }
import type from ekata.evaluation { EvaluationReport }
import from ekata.api { metrics }
import from ekata.evaluation_api { evaluation_results }
import from ...components.ui.button { Button }

def:pub Stat(label: str, value: str, detail: str = "") -> JsxElement {
    <article className="rounded-xl border bg-card p-5 shadow-sm"><p className="text-sm text-muted-foreground">{label}</p><strong className="mt-2 block text-3xl tracking-tight">{value}</strong><p className="mt-2 text-xs text-muted-foreground">{detail}</p></article>
}

def:pub MetricsPage -> JsxElement {
    has live: Metrics | None = None;
    has scores: EvaluationReport | None = None;
    has tick: int = 0;
    has error: str = "";
    async def refresh -> None {
        try { tick = tick + 1; live = await metrics(tick); scores = await evaluation_results(tick); error = ""; }
        except Exception as e { error = str(e); }
    }
    async can with entry { await refresh(); }
    <main className="mx-auto max-w-7xl space-y-6 p-5 lg:p-8">
        <header className="flex items-start justify-between gap-4"><div><h1 className="text-2xl font-bold">Impact & evaluation</h1><p className="mt-1 text-muted-foreground">Measured results, with the dataset and engine always visible.</p></div><Button variant="outline" onClick={lambda (e: MouseEvent) { refresh(); }}>Refresh</Button></header>
        {if error != "" { <p role="alert" className="rounded border border-red-500 p-3">{error}</p> }}
        <section><h2 className="mb-3 text-lg font-semibold">Current desk</h2><p className="mb-3 text-sm text-muted-foreground">Operational counters for this replay. These are not benchmark accuracy.</p>
            {if live is not None { <div className="grid gap-4 sm:grid-cols-3"><Stat label="Messages received" value={str(live.messages)} /><Stat label="Rescue incidents" value={str(live.incidents)} /><Stat label="Duplicate calls avoided" value={str(live.calls_saved)} detail="Rescue messages minus distinct incidents" /></div> }}
        </section>
        {if scores is None { <section className="rounded-xl border border-dashed p-8"><h2 className="font-semibold">No evaluation published yet</h2><p className="mt-2 text-muted-foreground">Results will appear after a labelled evaluation has been completed. No accuracy is assumed.</p></section> }}
        {if scores is not None {
            <section className="space-y-5">
                <div className="rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950"><strong>{scores.dataset_role + " · " + scores.mode + " mode"}</strong><p className="mt-1 text-sm">{scores.dataset + " · " + str(scores.messages) + " messages · " + scores.generated_at}</p></div>
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <Stat label="Merge precision" value={f"{scores.merge_precision * 100:.1f}%" if scores.predicted_pairs > 0 else "Not defined"} detail={str(scores.correct_pairs) + " correct / " + str(scores.predicted_pairs) + " predicted pairs"} />
                    <Stat label="Merge recall" value={f"{scores.merge_recall * 100:.1f}%" if scores.true_pairs > 0 else "Not defined"} detail={str(scores.correct_pairs) + " found / " + str(scores.true_pairs) + " true pairs"} />
                    <Stat label="Calls avoided" value={str(scores.calls_saved)} detail={str(scores.rescue_messages) + " rescue messages → " + str(scores.incidents) + " incidents"} />
                    <Stat label="Median processing time" value={f"{scores.median_latency_ms:.0f} ms"} detail={scores.mode + " engine"} />
                </div>
                <div className="grid gap-4 sm:grid-cols-3"><Stat label="Agent invocations" value={str(scores.agent_calls)} detail={str(scores.tokens) + " recorded tokens"} /><Stat label="Model cost estimate" value={f"${scores.cost_usd:.4f}" if scores.cost_available else ("No model calls" if scores.agent_calls == 0 else "Unavailable")} /><Stat label="Referee interventions" value={str(scores.interventions)} detail={str(scores.retries) + " retries · " + str(scores.failed_messages) + " processing failures"} /></div>
                <section className="overflow-x-auto rounded-xl border bg-card p-5"><h2 className="mb-3 text-lg font-semibold">Language breakdown</h2><table className="w-full text-left text-sm"><thead><tr className="border-b"><th className="p-2">Language</th><th className="p-2">Rescue messages</th><th className="p-2">Precision</th><th className="p-2">Recall</th><th className="p-2">Correct / true pairs</th></tr></thead><tbody>{for row in scores.languages { <tr key={row.language} className="border-b last:border-0"><td className="p-2 font-semibold">{row.language}</td><td className="p-2">{row.messages}</td><td className="p-2">{f"{row.precision * 100:.1f}%" if row.predicted_pairs > 0 else "—"}</td><td className="p-2">{f"{row.recall * 100:.1f}%" if row.true_pairs > 0 else "—"}</td><td className="p-2">{str(row.correct_pairs) + " / " + str(row.true_pairs)}</td></tr> }}</tbody></table></section>
                <section className="rounded-xl border bg-card p-5"><h2 className="mb-3 text-lg font-semibold">Flagged incidents in the call queue</h2><div className="flex flex-wrap gap-2">{for row in scores.critical { <span key={row.inc_id} className="rounded border bg-muted px-3 py-2 text-sm">{f"#{row.rank} " + row.inc_id + " · " + ", ".join(row.flags)}</span> }}</div></section>
                <section className="rounded-xl border bg-card p-5"><h2 className="font-semibold">What these numbers mean</h2><ul className="mt-3 list-disc space-y-2 pl-5 text-sm text-muted-foreground">{for note in scores.notes { <li key={note}>{note}</li> }}</ul><p className="mt-3 text-sm">{f"Appeal verdict accuracy: {scores.appeal_accuracy * 100:.1f}%" if scores.appeal_labels > 0 else "Appeal verdict accuracy: unavailable without verdict labels."}</p></section>
            </section>
        }}
    </main>
}
