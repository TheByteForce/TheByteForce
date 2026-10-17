"""Operator panel for recording the demo. Hidden unless the URL has ?ops.

It seeds the synthetic storm night and replays it one message every 1.5 s,
so every portal fills up as if the night were happening live.
"""

import from "react" { useEffect }
import type from ekata.views { DemoState }
import from ekata.api { load_demo, demo_state, replay_next }

def:pub OpsPanel -> JsxElement {
    has demo: DemoState | None = None;
    has running: bool = False;
    has busy: bool = False;
    has open: bool = True;
    has tick: int = 0;
    has note: str = "";

    async def read_state -> None {
        tick = tick + 1;
        try {
            demo = await demo_state(tick);
        } except Exception as ex {
            note = str(ex);
        }
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

    pos: int = demo.position if demo is not None else 0;
    total: int = demo.total if demo is not None else 0;
    clock: str = demo.storm_time if demo is not None else "";

    <aside
        className="fixed bottom-4 right-4 z-50 w-72 rounded-lg border border-border bg-card p-3 text-[13px] shadow-lg"
        aria-label="Operator panel"
    >
        <div className="flex items-center justify-between">
            <strong className="text-[15px]">Operator</strong>
            <button
                className="text-muted-foreground hover:text-foreground"
                onClick={lambda (e: MouseEvent) { open = not open; }}
            >
                {"Hide" if open else "Show"}
            </button>
        </div>
        {if open {
            <div className="mt-2 space-y-2">
                <p className="text-muted-foreground">
                    {f"Storm time {clock}, message {pos} of {total}"}
                </p>
                <div className="flex gap-2">
                    <button
                        className="flex-1 rounded-md border border-border px-2 py-1.5 font-semibold hover:bg-muted disabled:opacity-50"
                        disabled={busy}
                        onClick={lambda (e: MouseEvent) { do_load(); }}
                    >
                        Load storm night
                    </button>
                    <button
                        className="flex-1 rounded-md bg-primary px-2 py-1.5 font-semibold text-primary-foreground disabled:opacity-50"
                        onClick={lambda (e: MouseEvent) { running = not running; }}
                    >
                        {"Pause" if running else "Play"}
                    </button>
                </div>
                {if note != "" {
                    <p className="text-muted-foreground">{note}</p>
                }}
            </div>
        }}
    </aside>
}
