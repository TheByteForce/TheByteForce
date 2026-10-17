"""Shared live state for every page.

The provider pulses the live situation (new reports arrive on the server as
time passes), keeps a refresh tick, and remembers each portal's workspace:
the citizen's area, the officer's division, the relief group and the
district analyst. Pages read with `ctx.tick` as the cache key (the client
caches reads for 60 s) and re-read whenever it changes: after a pulse that
brought news, after any page calls `ctx.bump()` following a write, and every
few seconds otherwise.
"""

import from "react" { createContext, useContext, useEffect }
import type from ekata.live_feed { LiveState }
import from ekata.live_feed { situation_pulse }

glob DeskCtx: any = createContext(None);

def:pub use_desk -> any {
    return useContext(DeskCtx);
}

# A fresh cache key for reads that must not be served from the client cache.
def:pub fresh_tick -> int {
    return int(Date.now());
}

def:pub read_saved(key: str) -> str {
    try {
        v = localStorage.getItem(key);
        return v if v else "";
    } except Exception as ex {
        return "";
    }
}

def:pub save_value(key: str, value: str) -> None {
    try {
        localStorage.setItem(key, value);
    } except Exception as ex {
        return;
    }
}

# A citizen's last five reference numbers, newest first.
def:pub saved_refs -> list[str] {
    raw = read_saved("cc.refs");
    if raw == "" {
        return [];
    }
    return [r for r in raw.split(",") if r != ""];
}

def:pub remember_ref(ref: str) -> list[str] {
    refs = [ref] + [r for r in saved_refs() if r != ref];
    refs = refs[:5];
    save_value("cc.refs", ",".join(refs));
    return refs;
}

def:pub DeskProvider(children: any = None) -> JsxElement {
    has live: LiveState | None = None;
    has tick: int = 1;
    has error: str = "";
    has area: str = "";
    has ds: str = "";
    has group: str = "";
    has analyst: str = "Analyst A";
    has pulsing: bool = False;

    def bump -> None {
        tick = tick + 1;
    }

    async def pulse -> None {
        if pulsing {
            return;
        }
        pulsing = True;
        try {
            s = await situation_pulse(fresh_tick());
            live = s;
            error = "";
            bump();
        } except Exception as ex {
            error = "Could not reach the CrisisConnect server: " + str(ex);
        }
        pulsing = False;
    }

    async can with entry {
        document.title = "CrisisConnect · Flood response";
        area = read_saved("cc.area");
        ds = read_saved("cc.ds");
        group = read_saved("cc.group");
        a = read_saved("cc.analyst");
        if a != "" {
            analyst = a;
        }
        await pulse();
    }

    useEffect(
        lambda {
            timer = setInterval(lambda { pulse(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        []
    );

    value = {
        "live": live,
        "tick": tick,
        "error": error,
        "area": area,
        "ds": ds,
        "group": group,
        "analyst": analyst,
        "bump": lambda { bump(); },
        "setArea": lambda (v: str) { area = v; save_value("cc.area", v); },
        "setDs": lambda (v: str) { ds = v; save_value("cc.ds", v); },
        "setGroup": lambda (v: str) { group = v; save_value("cc.group", v); },
        "setAnalyst": lambda (v: str) { analyst = v; save_value("cc.analyst", v); }
    };
    <DeskCtx.Provider value={value}>{children}</DeskCtx.Provider>
}
