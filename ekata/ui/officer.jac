"""Division officer portal: pick a DS division once, then work its queue.

State lives here. Readers take a changing tick (the client caches reads for
60 s) and every write is followed by a re-fetch.
"""

import from "react" { useEffect }
import type from ekata.views { QueueRow, IncidentView }
import type from ekata.portal { DivisionView, RequestView }
import from ekata.api { incident_detail }
import from ekata.portal_api {
    divisions,
    officer_queue,
    incident_requests,
    resource_kinds
}
import from .atoms { PortalHeader }
import from .queue { OfficerQueue }
import from .incident { CasePanel }

def:pub OfficerPortal -> JsxElement {
    has ds: str = "";
    has ready: bool = False;
    has divs: list[DivisionView] = [];
    has queue: list[QueueRow] = [];
    has kinds: list[str] = [];
    has selected: str = "";
    has pinned: bool = False;
    has incident: IncidentView | None = None;
    has requests: list[RequestView] = [];
    has loadingCase: bool = False;
    has tick: int = 0;
    has error: str = "";

    async def read_all(division: str, want: str, hold: bool) -> None {
        t = int(Date.now());
        tick = t;
        try {
            divs = await divisions(t);
            if division == "" {
                error = "";
                return;
            }
            q = await officer_queue(division, t);
            queue = q;
            sel = want;
            ids: list[str] = [r.inc_id for r in q];
            if (sel == "" or not hold or sel not in ids) and len(q) > 0 {
                sel = q[0].inc_id;
            }
            if len(q) == 0 {
                sel = "";
            }
            selected = sel;
            if sel != "" {
                incident = await incident_detail(sel, t);
                requests = await incident_requests(sel, t);
            } else {
                incident = None;
                requests = [];
            }
            error = "";
        } except Exception as ex {
            error = "Could not reach the Ekata server: " + str(ex);
        }
    }

    async def open_case(incId: str) -> None {
        selected = incId;
        pinned = True;
        incident = None;
        loadingCase = True;
        await read_all(ds, incId, True);
        loadingCase = False;
    }

    def choose(v: str) -> None {
        ds = v;
        selected = "";
        pinned = False;
        incident = None;
        queue = [];
        try {
            localStorage.setItem("ekata.officer.ds", v);
        } except Exception as ex {
            error = "";
        }
        read_all(v, "", False);
    }

    def change_division -> None {
        ds = "";
        queue = [];
        incident = None;
        selected = "";
        pinned = False;
        try {
            localStorage.removeItem("ekata.officer.ds");
        } except Exception as ex {
            error = "";
        }
    }

    def on_changed(iv: IncidentView | None) -> None {
        if iv is not None and iv.inc_id == selected {
            incident = iv;
        }
        read_all(ds, selected, True);
    }

    def on_refresh -> None {
        read_all(ds, selected, True);
    }

    async can with entry {
        stored = "";
        try {
            got = localStorage.getItem("ekata.officer.ds");
            if got is not None {
                stored = str(got);
            }
        } except Exception as ex {
            stored = "";
        }
        ds = stored;
        try {
            kinds = await resource_kinds();
        } except Exception as ex {
            kinds = [];
        }
        await read_all(stored, "", False);
        ready = True;
    }

    # Refresh about every 5 s; re-registered when the division or case changes
    # so the callback never reads stale values.
    useEffect(
        lambda {
            timer = setInterval(lambda { read_all(ds, selected, pinned); }, 5000);
            return lambda { clearInterval(timer); };
        },
        [ds, selected, pinned]
    );

    desk_name: str = f"Divisional desk, {ds}";
    here: DivisionView | None = None;
    for d in divs {
        if d.ds == ds {
            here = d;
        }
    }
    gns: list[str] = here.gns if here is not None else [];

    if ds == "" {
        return
            <div className="min-h-dvh bg-background text-foreground">
                <PortalHeader portal="Division officer"/>
                <main className="mx-auto max-w-[900px] px-4 py-8 lg:px-6">
                    <h1 className="text-[28px] font-bold leading-tight">Which division do you cover?</h1>
                    <p className="mt-1 text-[15px] text-muted-foreground">
                        Choose once. This browser will remember it.
                    </p>
                    {if error != "" {
                        <p role="alert" className="mt-4 rounded-md border border-blocked/30 bg-blocked-soft p-3 text-[15px] font-semibold text-blocked">
                            {error}
                        </p>
                    }}
                    {if ready and len(divs) == 0 and error == "" {
                        <p className="mt-6 text-[15px] text-muted-foreground">
                            No divisions are listed yet.
                        </p>
                    }}
                    <ul className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
                        {for d in divs {
                            <li key={d.ds}>
                                <button
                                    type="button"
                                    className="w-full rounded-lg border border-border bg-card p-4 text-left hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                                    onClick={lambda (e: MouseEvent) { choose(d.ds); }}
                                >
                                    <span className="block text-[17px] font-semibold">{d.ds}</span>
                                    <span className="block text-[13px] text-muted-foreground">
                                        {d.district + " district"}
                                    </span>
                                    <span className="mt-2 block text-[15px]">
                                        {"1 open case" if d.open_count == 1 else f"{d.open_count} open cases"}
                                    </span>
                                </button>
                            </li>
                        }}
                    </ul>
                </main>
            </div>;
    }

    <div className="min-h-dvh bg-background text-foreground">
        <PortalHeader portal="Division officer" who={ds}>
            <button
                type="button"
                className="rounded-md px-2 py-1 text-[13px] font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-primary"
                onClick={lambda (e: MouseEvent) { change_division(); }}
            >
                Change division
            </button>
        </PortalHeader>
        {if error != "" {
            <div
                role="alert"
                className="border-b border-blocked/30 bg-blocked-soft px-4 py-2 text-[15px] font-semibold text-blocked lg:px-6"
            >
                {error}
            </div>
        }}
        <main className="mx-auto grid max-w-[1500px] grid-cols-1 gap-6 px-4 py-5 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)] lg:px-6">
            <div>
                <OfficerQueue
                    rows={queue}
                    selected={selected}
                    onSelect={lambda (id: str) { open_case(id); }}
                />
            </div>
            <div>
                <CasePanel
                    key={selected}
                    inc={incident}
                    requests={requests}
                    gns={gns}
                    kinds={kinds}
                    officer={desk_name}
                    loading={loadingCase}
                    onSelect={lambda (id: str) { open_case(id); }}
                    onChanged={on_changed}
                    onRefresh={on_refresh}
                />
            </div>
        </main>
    </div>
}
