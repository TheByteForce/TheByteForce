"""The Ekata Desk: one page that owns all state and every server call.

Readers take a changing tick argument (the client caches reads for 60 s) and
every writer call is followed by a full re-fetch.
"""

import from "react" { useEffect }
import from ekata.views { DemoState, ReplayStep, MsgView, QueueRow, TraceRow, IncidentView }
import from ekata.api {
    load_demo, demo_state, replay_next, call_queue, incident_detail, trace_since
}
import from .topbar { TopBar }
import from .inbox { Inbox }
import from .queue { CallQueue }
import from .incident { IncidentCard }
import from .trace { TraceStrip }

# Trace helpers live here, beside their only caller: plain helpers imported
# from another module don't cross into the client bundle.
def seq_of(r: TraceRow) -> int {
    return r.seq;
}

def merge_trace(existing: list[TraceRow], incoming: list[TraceRow]) -> list[TraceRow] {
    seen: list[int] = [];
    out: list[TraceRow] = [];
    for r in incoming + existing {
        if r.seq not in seen {
            seen = seen + [r.seq];
            out = out + [r];
        }
    }
    ordered = sorted(out, key=seq_of, reverse=True);
    return ordered[:300];
}

def trace_cursor(rows: list[TraceRow]) -> int {
    if len(rows) == 0 {
        return 0;
    }
    top: int = 0;
    for r in rows {
        if r.seq > top {
            top = r.seq;
        }
    }
    return top;
}

def:pub Desk -> JsxElement {
    has demo: DemoState | None = None;
    has step: ReplayStep | None = None;
    has inbox: list[MsgView] = [];
    has queue: list[QueueRow] = [];
    has trace: list[TraceRow] = [];
    has selected: str = "";
    has pinned: bool = False;
    has incident: IncidentView | None = None;
    has loadingIncident: bool = False;
    has running: bool = False;
    has busy: bool = False;
    has loadingDemo: bool = False;
    has tick: int = 0;
    has desk: str = "Desk A";
    has error: str = "";

    def next_tick -> int {
        t = tick + 1;
        tick = t;
        return t;
    }

    def add_message(m: MsgView | None) -> None {
        if m is None {
            return;
        }
        mv: MsgView = m;
        for x in inbox {
            if x.msg_id == mv.msg_id {
                return;
            }
        }
        inbox = ([mv] + inbox)[:300];
    }

    def apply_step(r: ReplayStep) -> None {
        step = r;
        add_message(r.message);
        if len(r.queue) > 0 {
            queue = r.queue;
        }
        if len(r.new_trace) > 0 {
            trace = merge_trace(trace, r.new_trace);
        }
    }

    # Re-read everything the screen shows. Called after every writer call.
    async def refresh -> None {
        t = next_tick();
        try {
            d = await demo_state(t);
            demo = d;
            q = await call_queue(t);
            queue = q;
            fresh = await trace_since(trace_cursor(trace));
            if len(fresh) > 0 {
                trace = merge_trace(trace, fresh);
            }
            sel = selected;
            # Until a person picks an incident, the card follows the top of the queue.
            if (sel == "" or not pinned) and len(q) > 0 {
                sel = q[0].inc_id;
                selected = sel;
            }
            if sel != "" {
                iv = await incident_detail(sel, t);
                if iv is None and len(q) > 0 and sel != q[0].inc_id {
                    sel = q[0].inc_id;
                    selected = sel;
                    iv = await incident_detail(sel, t);
                }
                incident = iv;
            } else {
                incident = None;
            }
            error = "";
        } except Exception as ex {
            error = "Could not reach the Ekata server: " + str(ex);
        }
    }

    async def do_load -> None {
        if loadingDemo or busy {
            return;
        }
        loadingDemo = True;
        running = False;
        error = "";
        try {
            d = await load_demo();
            demo = d;
            step = None;
            inbox = [];
            queue = [];
            trace = [];
            selected = "";
            pinned = False;
            incident = None;
            await refresh();
        } except Exception as ex {
            error = "Could not load the demo data: " + str(ex);
        }
        loadingDemo = False;
    }

    async def replay_tick -> None {
        if busy or loadingDemo or not running {
            return;
        }
        busy = True;
        try {
            r = await replay_next(1);
            apply_step(r);
            if r.done {
                running = False;
            }
            await refresh();
        } except Exception as ex {
            running = False;
            error = "Replay stopped: " + str(ex);
        }
        busy = False;
    }

    async def toggle_replay -> None {
        if running {
            running = False;
            return;
        }
        error = "";
        needs_seed = True;
        if demo is not None and demo.seeded {
            needs_seed = False;
        }
        if needs_seed {
            await do_load();
        }
        running = True;
        replay_tick();
    }

    async def select_inc(incId: str) -> None {
        selected = incId;
        pinned = True;
        incident = None;
        loadingIncident = True;
        t = next_tick();
        try {
            incident = await incident_detail(incId, t);
            error = "";
        } except Exception as ex {
            error = "Could not open the incident: " + str(ex);
        }
        loadingIncident = False;
    }

    def on_sent(r: ReplayStep) -> None {
        apply_step(r);
        refresh();
    }

    def on_changed(iv: IncidentView | None) -> None {
        if iv is not None and iv.inc_id == selected {
            incident = iv;
        }
        refresh();
    }

    async def poll -> None {
        if busy or running or loadingDemo {
            return;
        }
        await refresh();
    }

    async can with entry {
        await refresh();
    }

    # Replay clock: one step about every 1.5 s while running; replay_tick guards overlap.
    useEffect(
        lambda {
            timer = setInterval(lambda { replay_tick(); }, 1500);
            return lambda { clearInterval(timer); };
        },
        [running]
    );

    # Slow background refresh so other desks' changes show up when idle.
    useEffect(
        lambda {
            timer = setInterval(lambda { poll(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        []
    );

    # Derived values (plain locals, not state).
    cur_pos: int = 0;
    cur_total: int = 0;
    clock: str = "";
    is_locked: bool = False;
    is_done: bool = False;
    if demo is not None {
        cur_pos = demo.position;
        cur_total = demo.total;
        clock = demo.storm_time;
    }
    if step is not None {
        if step.total > 0 and cur_total == 0 {
            cur_pos = step.position;
            cur_total = step.total;
        }
        if step.storm_time != "" {
            clock = step.storm_time;
        }
        is_locked = running and step.locked;
        is_done = step.done;
    }
    if cur_total > 0 and cur_pos >= cur_total {
        is_done = True;
    }
    known_ids: list[str] = [r.inc_id for r in queue];

    <div className="flex min-h-screen flex-col bg-background text-foreground lg:h-screen">
        <TopBar
            stormTime={clock}
            position={cur_pos}
            total={cur_total}
            running={running}
            locked={is_locked}
            finished={is_done}
            busy={busy}
            loading={loadingDemo}
            onLoad={lambda { do_load(); }}
            onToggle={lambda { toggle_replay(); }}
        />
        {if error != "" {
            <div
                role="alert"
                className="border-b border-red-600 bg-red-50 px-4 py-2 text-sm font-semibold text-red-900 dark:bg-red-950 dark:text-red-100 lg:px-6"
            >
                {error}
            </div>
        }}
        <main className="grid min-h-[26rem] flex-1 grid-cols-1 gap-4 p-4 lg:min-h-0 lg:grid-cols-12 lg:grid-rows-[minmax(0,1fr)] lg:px-6">
            <section aria-label="Inbox" className="lg:col-span-3 lg:min-h-0">
                <Inbox messages={inbox} onSent={on_sent} />
            </section>
            <section aria-label="Call queue" className="lg:col-span-4 lg:min-h-0">
                <CallQueue rows={queue} selected={selected} onSelect={lambda (id: str) { select_inc(id); }} />
            </section>
            <section aria-label="Incident card" className="lg:col-span-5 lg:min-h-0">
                <IncidentCard
                    key={selected}
                    inc={incident}
                    loading={loadingIncident}
                    desk={desk}
                    onDesk={lambda (v: str) { desk = v; }}
                    onSelect={lambda (id: str) { select_inc(id); }}
                    onChanged={on_changed}
                />
            </section>
        </main>
        <TraceStrip
            rows={trace}
            knownIds={known_ids}
            onSelect={lambda (id: str) { select_inc(id); }}
        />
    </div>
}
