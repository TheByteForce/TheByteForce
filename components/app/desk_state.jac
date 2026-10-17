"""Shared desk state for every page: the storm-night replay, the acting desk,
and a refresh tick.

Pages read data with `ctx.tick` as the cache key (the client caches reads for
60 s), and re-read whenever the tick changes: after each replay step, after
any page calls `ctx.bump()` following a write, and every few seconds when idle.
"""

import from "react" { createContext, useContext, useEffect }
import type from ekata.views { DemoState }
import from ekata.api { load_demo, demo_state, replay_next }

glob DeskCtx: any = createContext(None);

def:pub use_desk -> any {
    return useContext(DeskCtx);
}

def:pub DeskProvider(children: any = None) -> JsxElement {
    has demo: DemoState | None = None;
    has running: bool = False;
    has busy: bool = False;
    has loading: bool = False;
    has tick: int = 1;
    has error: str = "";
    has desk: str = "Desk A";

    def bump -> None {
        tick = tick + 1;
    }

    async def read_state -> None {
        try {
            demo = await demo_state(tick);
            error = "";
        } except Exception as ex {
            error = "Could not reach the CrisisConnect server: " + str(ex);
        }
    }

    async def step_once -> None {
        if busy or loading or not running {
            return;
        }
        busy = True;
        try {
            r = await replay_next(1);
            if r.done {
                running = False;
            }
            bump();
            await read_state();
        } except Exception as ex {
            running = False;
            error = "Replay stopped: " + str(ex);
        }
        busy = False;
    }

    async def load_data -> None {
        if loading or busy {
            return;
        }
        loading = True;
        running = False;
        try {
            demo = await load_demo();
            error = "";
            bump();
        } except Exception as ex {
            error = "Could not load the demo data: " + str(ex);
        }
        loading = False;
    }

    async def toggle_replay -> None {
        if running {
            running = False;
            return;
        }
        if demo is None or not demo.seeded {
            await load_data();
        }
        running = True;
        step_once();
    }

    def idle_refresh -> None {
        if running or busy or loading {
            return;
        }
        bump();
        read_state();
    }

    async can with entry {
        document.title = "CrisisConnect · Flood response desk";
        await read_state();
    }

    # Replay clock: one message about every 1.5 s while running.
    useEffect(
        lambda {
            timer = setInterval(lambda { step_once(); }, 1500);
            return lambda { clearInterval(timer); };
        },
        [running]
    );

    # Idle refresh so changes made at other desks show up.
    useEffect(
        lambda {
            timer = setInterval(lambda { idle_refresh(); }, 6000);
            return lambda { clearInterval(timer); };
        },
        []
    );

    value = {
        "demo": demo,
        "running": running,
        "busy": busy,
        "loading": loading,
        "tick": tick,
        "error": error,
        "desk": desk,
        "load": lambda { load_data(); },
        "toggle": lambda { toggle_replay(); },
        "bump": lambda { bump(); },
        "setDesk": lambda (d: str) { desk = d; }
    };
    <DeskCtx.Provider value={value}>{children}</DeskCtx.Provider>
}
