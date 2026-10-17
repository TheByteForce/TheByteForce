"""The household story: one verified record from first SOS to delivery and the
appeals that cite it. Each step shows where it sits in the chain
evidence, agent proposal, rule applied, human decision, action.
"""

import from "react" { useEffect }
import from ekata.portal_api { household_timeline }
import type from ekata.timeline { HouseholdTimeline, TimelineStep }
import from .atoms { Chip, VulnerableBadge, tone_for, people_label }

def:pub stage_tone(stage: str) -> str {
    if stage == "Evidence" {
        return "border-border bg-muted text-foreground";
    }
    if stage == "Agent proposal" {
        return "border-[#1F5F7A]/30 bg-accent text-[#1F5F7A]";
    }
    if stage == "Rule applied" {
        return "border-alert/40 bg-alert-soft text-[#8A3306]";
    }
    if stage == "Human decision" {
        return "border-ok/30 bg-ok-soft text-ok";
    }
    return "border-[#43204F]/25 bg-[#F6EEF8] text-[#43204F]";
}

def:pub outcome_word(outcome: str) -> str {
    words = {
        "APPLIED": "",
        "BLOCKED": "Blocked",
        "NEEDS_HUMAN": "Sent to a person",
        "NEW_INCIDENT": "New case",
        "READ_ONLY": ""
    };
    return words.get(outcome, "");
}

def:pub StepRow(s: TimelineStep) -> JsxElement {
    <li className="relative grid grid-cols-[56px_1fr] gap-3 pb-5 last:pb-0">
        <span className="pt-0.5 text-[13px] tabular-nums text-muted-foreground">{s.time}</span>
        <div className="min-w-0 border-l border-border pl-4">
            <div className="flex flex-wrap items-center gap-2">
                <span className={"rounded-md border px-2 py-0.5 text-[12px] font-semibold " + stage_tone(s.stage)}>
                    {s.stage}
                </span>
                <span className="text-[15px] font-semibold">{s.title}</span>
                {if outcome_word(s.outcome) != "" {
                    <Chip label={outcome_word(s.outcome)} tone={tone_for("blocked" if s.outcome == "BLOCKED" else "alert")}/>
                }}
            </div>
            <p className="mt-1 text-[13px] text-muted-foreground">
                {s.actor + (f", {s.model}" if s.model != "" and s.model not in ["human", "rules"] else "") + (", rules" if s.model == "rules" else "")}
            </p>
            {if s.detail != "" {
                <p className="mt-1 whitespace-pre-wrap break-words text-[14px] leading-relaxed">{s.detail}</p>
            }}
        </div>
    </li>
}

def:pub HouseholdStory(incId: str) -> JsxElement {
    has story: HouseholdTimeline | None = None;
    has error: str = "";

    async def load -> None {
        try {
            story = await household_timeline(incId, int(Date.now()));
            error = "";
        } except Exception as e {
            error = "Could not load the household story.";
        }
    }

    async can with [incId] entry {
        await load();
    }

    useEffect(
        lambda {
            timer = setInterval(lambda { load(); }, 6000);
            return lambda { clearInterval(timer); };
        },
        [incId]
    );

    if story is None {
        return <p className="text-[14px] text-muted-foreground">{error if error != "" else "Loading the household story"}</p>;
    }
    <StoryBody story={story}/>
}

def:pub StoryBody(story: HouseholdTimeline) -> JsxElement {
    <section className="rounded-xl border border-border bg-card" aria-label="Household story">
        <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-4">
            <div className="min-w-0">
                <h2 className="text-[17px] font-semibold">Household record</h2>
                <p className="mt-1 text-[14px] leading-relaxed">{story.record}</p>
                <div className="mt-2 flex flex-wrap items-center gap-2">
                    <Chip
                        label={"Verified by phone" if story.verified else "Not verified yet"}
                        tone={tone_for("ok" if story.verified else "alert")}
                    />
                    <span className="text-[13px] text-muted-foreground">
                        {f"{story.messages} messages merged, {people_label(story.headcount).lower()}"}
                        {if len(story.appeals) > 0 {
                            <span>{", cited by appeal " + ", ".join(story.appeals)}</span>
                        }}
                    </span>
                    {for v in story.vulnerable {
                        <VulnerableBadge key={v} flag={v}/>
                    }}
                </div>
            </div>
            <a
                href="/graph"
                target="_blank"
                rel="noreferrer"
                className="shrink-0 rounded-md border border-border px-3 py-1.5 text-[13px] font-semibold text-primary hover:bg-muted"
            >
                Open the live Jac graph
            </a>
        </div>
        <div className="px-5 py-4">
            <p className="mb-4 text-[13px] text-muted-foreground">
                Evidence, then agent proposals, then the rules that checked them, then what people decided and what happened.
            </p>
            <ol>
                {for s in story.steps {
                    <StepRow key={f"{s.seq}-{s.time}-{s.title}"} s={s}/>
                }}
            </ol>
        </div>
    </section>
}
