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
    all_requests,
    resource_kinds
}
import from .atoms { RequestBadge, pretty, people_label }
import from .shell { AppShell, WorkspaceSelect, Surface }
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
    has allReqs: list[RequestView] = [];
    has page: str = "queue";
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
            everything = await all_requests(t);
            allReqs = [r for r in everything if r.inc_id in ids];
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
        page = "case";
        pinned = True;
        incident = None;
        loadingCase = True;
        await read_all(ds, incId, True);
        loadingCase = False;
    }

    def choose(v: str) -> None {
        ds = v;
        page = "queue";
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

    nav = [
        ["queue", "Call queue", "call"],
        ["case", "Open case", "people"],
        ["requests", "Relief requests", "truck"]
    ];
    page_title = "Call queue";
    page_sub = f"{len(queue)} households waiting in {ds}, most vulnerable first" if len(queue) != 1 else f"1 household waiting in {ds}";
    if page == "case" {
        page_title = "Open case";
        page_sub = "What was said, and what you can do about it.";
    }
    if page == "requests" {
        page_title = "Relief requests";
        page_sub = f"Everything asked of relief groups for households in {ds}.";
    }
    if ds == "" {
        page_title = "Division officer desk";
        page_sub = "";
    }

    <AppShell
        tone="officer"
        tagline="Division officer desk"
        nav={nav}
        active={page}
        onNav={lambda (k: str) { page = k; }}
        title={page_title}
        subtitle={page_sub}
        workspaceLabel="Your division"
        workspace={<WorkspaceSelect
            value={ds}
            options={[d.ds for d in divs]}
            onPick={choose}
            placeholder="Choose your division"
        />}
    >
        {if error != "" {
            <p role="alert" className="mb-5 rounded-xl bg-blocked-soft px-4 py-3 text-[15px] font-semibold text-blocked">
                {error}
            </p>
        }}
        {if ds == "" {
            <div className="rounded-xl border border-border bg-card px-5 py-16 text-center">
                <p className="text-[17px] font-semibold">Choose your division in the sidebar to see its households</p>
                <p className="mt-1 text-[15px] text-muted-foreground">
                    This browser will remember it for next time.
                </p>
                {if ready and len(divs) == 0 and error == "" {
                    <p className="mt-3 text-[13px] text-muted-foreground">No divisions are listed yet.</p>
                }}
            </div>
        }}
        {if ds != "" and page == "queue" {
            <OfficerQueue
                rows={queue}
                selected={selected}
                onSelect={lambda (id: str) { open_case(id); }}
            />
        }}
        {if ds != "" and page == "case" {
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
        }}
        {if ds != "" and page == "requests" {
            <Surface>
                {if len(allReqs) == 0 {
                    <p className="py-6 text-center text-[15px] text-muted-foreground">
                        No requests have been sent to relief groups yet.
                    </p>
                }}
                {if len(allReqs) > 0 {
                    <ul className="-my-5">
                        {for r in allReqs {
                            <li key={r.req_id} className="border-b border-border py-4 last:border-0">
                                <div className="flex flex-wrap items-center gap-2">
                                    <RequestBadge status={r.status}/>
                                    <span className="text-[15px] font-semibold">{pretty(r.need)}</span>
                                    <span className="text-[15px] text-muted-foreground">
                                        {(r.place if r.place != "" else r.inc_id) + ", " + people_label(r.headcount)}
                                    </span>
                                </div>
                                <p className="mt-1 text-[15px]">
                                    {r.ngo if r.ngo != "" else "No group is assigned yet"}
                                    {if r.ngo_contact != "" {
                                        <span className="text-muted-foreground">{", call " + r.ngo_contact}</span>
                                    }}
                                </p>
                                {if r.reason != "" {
                                    <p className="mt-0.5 text-[13px] text-muted-foreground">{r.reason}</p>
                                }}
                            </li>
                        }}
                    </ul>
                }}
            </Surface>
        }}
    </AppShell>
}
