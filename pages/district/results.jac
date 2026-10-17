"""District: how well the system is doing, measured, plus what the agents learned."""

import from "@hugeicons/core-free-icons" { ChartLineData01Icon, AiBrain01Icon, CallIcon, InboxIcon, GitMergeIcon }
import type from crisisconnect.views { Metrics }
import type from crisisconnect.evaluation { EvaluationReport }
import type from crisisconnect.memory { RuleStat, Precedent }
import from crisisconnect.api { metrics }
import from crisisconnect.evaluation_api { evaluation_results }
import from crisisconnect.memory_api { rule_stats, precedent_stats }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ...components.app.desk_state { use_desk }
import from ...components.app.page_parts { PageHero, EmptyNote, IconChip }

def:pub pct(x: float) -> str {
    return f"{round(x * 100)}%";
}

def:pub Stat(label: str, value: str, note: str = "") -> JsxElement {
    <div className="rounded-lg border pt-4 pb-4 pl-4 pr-4">
        <p className="text-sm text-muted-foreground">{label}</p>
        <p className="mt-1 text-3xl font-semibold tabular-nums">{value}</p>
        {if note != "" {
            <p className="mt-1 text-xs text-muted-foreground">{note}</p>
        }}
    </div>
}

def:pub ResultsPage -> JsxPage {
    ctx: any = use_desk();
    has m: Metrics | None = None;
    has ev: EvaluationReport | None = None;
    has rules: list[RuleStat] = [];
    has precedents: list[Precedent] = [];

    async can with [ctx.tick] entry {
        try {
            m = await metrics(ctx.tick);
            ev = await evaluation_results(ctx.tick);
            rules = await rule_stats(ctx.tick);
            precedents = await precedent_stats(ctx.tick);
        } except Exception as ex {
            m = m;
        }
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District coordination · Results"
            title="Is it working? Measured, not claimed."
            description="Live counts from the desk, the latest evaluation against hand-labelled messages, and what the agents have learned from officers' decisions."
            image="/static/assets/images/desk-operators.jpg"
            imageAlt="Duty officers working at screens in an operations centre"
            capsules={[
                [f"{m.calls_saved if m else 0} calls saved by merging", "green"],
                [(pct(ev.merge_precision) + " merge precision") if ev else "Evaluation not run yet", "blue"],
                [(pct(ev.merge_recall) + " merge recall") if ev else "", "violet"] if ev else ["Live counts below", "slate"]
            ]}
        />

        <Card>
            <CardHeader>
                <div className="flex items-center gap-4">
                    <IconChip icon={InboxIcon} tone="blue" />
                    <div className="flex flex-col gap-1">
                        <CardTitle>The desk right now</CardTitle>
                        <CardDescription>Counted live from the shared picture.</CardDescription>
                    </div>
                </div>
            </CardHeader>
            <CardContent className="grid grid-cols-1 gap-4 sm:grid-cols-4">
                <Stat label="Messages" value={str(m.messages) if m else "—"} note={f"{m.rescue_messages} asking for rescue" if m else ""} />
                <Stat label="Cases" value={str(m.incidents) if m else "—"} note="Merged from those messages" />
                <Stat label="Calls needed" value={str(m.calls_needed) if m else "—"} />
                <Stat label="Calls saved" value={str(m.calls_saved) if m else "—"} note="Duplicate reports folded into one case" />
            </CardContent>
        </Card>

        {if ev is None {
            <EmptyNote
                title="No evaluation published yet"
                description="Run tools/evaluate.jac to score merging, ranking and appeal checks against the labelled messages."
                icon={ChartLineData01Icon}
            />
        } else {
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-4">
                        <IconChip icon={GitMergeIcon} tone="violet" />
                        <div className="flex flex-col gap-1">
                            <CardTitle>Evaluation</CardTitle>
                            <CardDescription>{f"{ev.dataset} · {ev.mode} mode · {ev.generated_at}"}</CardDescription>
                        </div>
                    </div>
                </CardHeader>
                <CardContent className="flex flex-col gap-6">
                    <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                        <Stat label="Merge precision" value={pct(ev.merge_precision)} note={f"{ev.correct_pairs} of {ev.predicted_pairs} merges right"} />
                        <Stat label="Merge recall" value={pct(ev.merge_recall)} note={f"{ev.correct_pairs} of {ev.true_pairs} true pairs found"} />
                        <Stat label="Calls saved" value={str(ev.calls_saved)} />
                        <Stat label="Median latency" value={f"{round(ev.median_latency_ms)} ms"} />
                        <Stat label="Agent calls" value={str(ev.agent_calls)} note={f"{ev.tokens} tokens"} />
                        <Stat label="Cost" value={f"${ev.cost_usd:.2f}" if ev.cost_available else "—"} />
                        <Stat label="Appeal accuracy" value={pct(ev.appeal_accuracy)} note={f"{ev.appeal_labels} labelled appeals"} />
                        <Stat label="Interventions" value={str(ev.interventions)} note={f"{ev.retries} retries, {ev.failed_messages} failed"} />
                    </div>
                    {if len(ev.languages) > 0 {
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Language</TableHead>
                                    <TableHead className="text-right">Messages</TableHead>
                                    <TableHead className="text-right">Precision</TableHead>
                                    <TableHead className="text-right">Recall</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {for l in ev.languages {
                                    <TableRow key={l.language}>
                                        <TableCell className="font-medium uppercase">{l.language}</TableCell>
                                        <TableCell className="text-right tabular-nums">{str(l.messages)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{pct(l.precision)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{pct(l.recall)}</TableCell>
                                    </TableRow>
                                }}
                            </TableBody>
                        </Table>
                    }}
                    {if len(ev.notes) > 0 {
                        <ul className="list-disc pl-5 text-xs text-muted-foreground">
                            {for n in ev.notes {
                                <li key={n}>{n}</li>
                            }}
                        </ul>
                    }}
                </CardContent>
            </Card>
        }}

        <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-4">
                        <IconChip icon={CallIcon} tone="amber" />
                        <div className="flex flex-col gap-1">
                            <CardTitle>Referee rules</CardTitle>
                            <CardDescription>How often each safety rule let an agent act, blocked it, or sent it to a person.</CardDescription>
                        </div>
                    </div>
                </CardHeader>
                <CardContent>
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Rule</TableHead>
                                <TableHead className="text-right">Applied</TableHead>
                                <TableHead className="text-right">Blocked</TableHead>
                                <TableHead className="text-right">To a person</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {for r in rules {
                                <TableRow key={r.rule}>
                                    <TableCell className="font-mono">{r.rule}</TableCell>
                                    <TableCell className="text-right tabular-nums">{str(r.applied)}</TableCell>
                                    <TableCell className="text-right tabular-nums">{str(r.blocked)}</TableCell>
                                    <TableCell className="text-right tabular-nums">{str(r.needs_human)}</TableCell>
                                </TableRow>
                            }}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-4">
                        <IconChip icon={AiBrain01Icon} tone="violet" />
                        <div className="flex flex-col gap-1">
                            <CardTitle>What officers taught the agents</CardTitle>
                            <CardDescription>Merge decisions the resolver now uses as precedent.</CardDescription>
                        </div>
                    </div>
                </CardHeader>
                <CardContent className="flex flex-col gap-2">
                    {if len(precedents) == 0 {
                        <p className="text-sm text-muted-foreground">No officer decisions recorded yet.</p>
                    }}
                    {for p in precedents {
                        <div key={p.pattern} className="rounded-lg border pt-3 pb-3 pl-3 pr-3 text-sm">
                            <p className="font-medium">{p.pattern}</p>
                            <p className="text-muted-foreground">{f"{p.approved} approved, {p.rejected} rejected"}</p>
                        </div>
                    }}
                </CardContent>
            </Card>
        </div>
    </div>
}
