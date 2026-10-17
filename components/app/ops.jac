"""Operator panel for presenting the demo. Hidden unless the URL has ?ops.

Guided story first: one household through seven checkpoints, each step run by
the real pipeline. The full 94-message storm night replay stays available
below it.
"""

import from "react" { useEffect }
import from .desk_state { use_desk }
import type from ekata.views { DemoState }
import type from ekata.scenario { ScenarioView }
import from ekata.api { load_demo, demo_state, replay_next }
import from ekata.scenario_api { scenario_reset, scenario_next, scenario_state }

def:pub OpsPanel -> JsxElement {
    ctx: any = use_desk();
    has story: ScenarioView | None = None;
    has demo: DemoState | None = None;
    has running: bool = False;
    has busy: bool = False;
    has open: bool = True;
    has showReplay: bool = False;
    has tick: int = 0;
    has note: str = "";

    async def read_state -> None {
        tick = tick + 1;
        try {
            story = await scenario_state(tick);
            demo = await demo_state(tick);
        } except Exception as ex {
            note = str(ex);
        }
    }

    async def story_reset -> None {
        busy = True;
        running = False;
        try {
            story = await scenario_reset();
            ctx.bump();
            note = "";
        } except Exception as ex {
            note = "Reset failed: " + str(ex);
        }
        busy = False;
    }

    async def story_next -> None {
        busy = True;
        try {
            story = await scenario_next();
            ctx.bump();
            note = "";
        } except Exception as ex {
            note = "That step failed: " + str(ex);
        }
        busy = False;
    }

    async def do_load -> None {
        busy = True;
        running = False;
        try {
            demo = await load_demo();
            note = "Storm night loaded";
        } except Exception as ex {
            note = "Load failed: " + str(ex);
        }
        busy = False;
    }

    async def step_once -> None {
        if busy or not running {
            return;
        }
        busy = True;
        try {
            r = await replay_next(1);
            if r.done {
                running = False;
                note = "Replay finished";
            }
            await read_state();
        } except Exception as ex {
            running = False;
            note = "Replay stopped: " + str(ex);
        }
        busy = False;
    }

    async can with entry {
        await read_state();
    }

    useEffect(
        lambda {
            timer = setInterval(lambda { step_once(); }, 1500);
            return lambda { clearInterval(timer); };
        },
        [running]
    );

    step: int = story.step if story is not None else 0;
    total: int = story.total if story is not None else 7;
    pos: int = demo.position if demo is not None else 0;
    dtotal: int = demo.total if demo is not None else 0;

    <aside
        className="fixed bottom-4 right-4 z-[1000] w-[380px] max-w-[calc(100vw-2rem)] rounded-xl border border-border bg-card p-4 text-[13px] shadow-lg"
        aria-label="Operator panel"
    >
        <div className="flex items-center justify-between">
            <strong className="text-[15px]">Guided story</strong>
            <button
                className="text-muted-foreground hover:text-foreground"
                onClick={lambda (e: MouseEvent) { open = not open; }}
            >
                {"Hide" if open else "Show"}
            </button>
        </div>
        {if open {
            <div className="mt-3 space-y-3">
                <div className="flex items-center gap-1" aria-label={f"Step {step} of {total}"}>
                    {for i in range(total) {
                        <span
                            key={i}
                            className={"h-1.5 flex-1 rounded-full " + ("bg-primary" if i < step else "bg-muted")}
                        ></span>
                    }}
                </div>
                {if story is not None {
                    <div>
                        <p className="text-[13px] text-muted-foreground">{f"Step {step} of {total}"}</p>
                        <p className="text-[15px] font-semibold leading-snug">
                            {story.title if story.title != "" else "One household, from first SOS to appeal check"}
                        </p>
                        {if story.happened != "" {
                            <p className="mt-1.5 leading-relaxed">{story.happened}</p>
                        }}
                        <p className="mt-1.5 rounded-md bg-muted px-2.5 py-2 leading-relaxed">
                            {"Show: " + story.show}
                        </p>
                        {if story.inc_id != "" {
                            <p className="mt-1.5 text-muted-foreground">
                                {f"Household {story.inc_id}, citizen reference {story.ref}"}
                            </p>
                        }}
                    </div>
                }}
                <div className="flex gap-2">
                    <button
                        className="flex-1 rounded-md border border-border px-2 py-2 font-semibold hover:bg-muted disabled:opacity-50"
                        disabled={busy}
                        onClick={lambda (e: MouseEvent) { story_reset(); }}
                    >
                        Start over
                    </button>
                    <button
                        className="flex-1 rounded-md bg-primary px-2 py-2 font-semibold text-primary-foreground disabled:opacity-50"
                        disabled={busy or step >= total}
                        onClick={lambda (e: MouseEvent) { story_next(); }}
                    >
                        {"Working..." if busy else ("Done" if step >= total else "Next step")}
                    </button>
                </div>
                <div className="flex flex-wrap gap-x-3 gap-y-1">
                    <a className="font-semibold text-primary hover:underline" href="/citizen?ops">Citizen</a>
                    <a className="font-semibold text-primary hover:underline" href="/officer?ops">Officer</a>
                    <a className="font-semibold text-primary hover:underline" href="/ngo?ops">Relief group</a>
                    <a className="font-semibold text-primary hover:underline" href="/district?ops">District</a>
                    <a className="font-semibold text-primary hover:underline" href="/graph" target="_blank" rel="noreferrer">Jac graph</a>
                </div>
                <div className="border-t border-border pt-2">
                    <button
                        className="text-muted-foreground hover:text-foreground"
                        onClick={lambda (e: MouseEvent) { showReplay = not showReplay; }}
                    >
                        {"Hide full storm night" if showReplay else "Full storm night replay"}
                    </button>
                    {if showReplay {
                        <div className="mt-2 space-y-2">
                            <p className="text-muted-foreground">{f"Message {pos} of {dtotal}"}</p>
                            <div className="flex gap-2">
                                <button
                                    className="flex-1 rounded-md border border-border px-2 py-1.5 font-semibold hover:bg-muted disabled:opacity-50"
                                    disabled={busy}
                                    onClick={lambda (e: MouseEvent) { do_load(); }}
                                >
                                    Load storm night
                                </button>
                                <button
                                    className="flex-1 rounded-md border border-border px-2 py-1.5 font-semibold hover:bg-muted"
                                    onClick={lambda (e: MouseEvent) { running = not running; }}
                                >
                                    {"Pause" if running else "Play"}
                                </button>
                            </div>
                        </div>
                    }}
                </div>
                {if note != "" {
                    <p className="text-muted-foreground">{note}</p>
                }}
            </div>
        }}
    </aside>
}
