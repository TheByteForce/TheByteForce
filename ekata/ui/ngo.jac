"""Relief group portal: a registered group's coordinator, on a laptop.

Pick the group in the sidebar, then answer the requests the matcher sent to it:
accept or decline, then mark on the way and delivered.
"""

import from "react" { useEffect }
import from ekata.portal_api { ngos, ngo_requests, respond_request }
import type from ekata.portal { NgoView, RequestView }
import from .atoms { Empty, RequestBadge, VulnerableBadge, people_label, pretty }
import from .ngo_map { NgoMapPage }
import from .shell { AppShell, WorkspaceSelect, Surface }

glob OFFICE_KEY: str = "ekata.ngo.office";

def:pub load_office -> str {
    try {
        v = localStorage.getItem(OFFICE_KEY);
        return str(v) if v is not None else "";
    } except Exception {
        return "";
    }
}

def:pub save_office(name: str) -> None {
    try {
        if name == "" {
            localStorage.removeItem(OFFICE_KEY);
        } else {
            localStorage.setItem(OFFICE_KEY, name);
        }
    } except Exception {
        ok = False;
    }
}

def:pub ActionButton(
    label: str, onPress: Callable[[], None], busy: bool = False, quiet: bool = False
) -> JsxElement {
    cls = (
        "min-h-10 rounded-lg border border-border bg-card px-4 text-[15px] font-semibold text-foreground hover:bg-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        if quiet
        else "min-h-10 rounded-lg bg-[#43204F] px-4 text-[15px] font-semibold text-white hover:bg-[#351940] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    );
    <button
        type="button"
        className={cls + " disabled:opacity-60"}
        disabled={busy}
        onClick={lambda (e: MouseEvent) { onPress(); }}
    >
        {label}
    </button>
}

# ---------- One request card ----------

def:pub RequestCard(
    r: RequestView, office: str, busy: bool, onAct: Callable[[str, str], None],
    onMap: Callable[[], None] = lambda { }
) -> JsxElement {
    mine = r.ngo == office;
    passed = (office in r.declined_by) and not mine;
    fresh = r.status == "REQUESTED" and not passed;
    <article
        className={
            "rounded-xl border border-border p-5 "
            + ("bg-muted " if passed else "bg-card ")
            + ("border-l-4 border-l-alert" if fresh else "")
        }
    >
        {if passed {
            <p className="text-[15px] text-muted-foreground">
                {pretty(r.need)}{" at "}{r.place}{". You declined; now with "}{r.ngo if r.ngo != "" else "another group"}{"."}
            </p>
        } else {
            <div>
                <div className="flex flex-wrap items-start justify-between gap-2">
                    <p className="text-[20px] font-semibold leading-tight">{pretty(r.need)}</p>
                    <RequestBadge status={r.status}/>
                </div>
                <p className="mt-1 text-[15px]">
                    {r.place}{". "}{people_label(r.headcount)}{"."}
                </p>
                {if len(r.vulnerable) > 0 {
                    <div className="mt-2 flex flex-wrap gap-2">
                        {for v in r.vulnerable {
                            <VulnerableBadge key={v} flag={v}/>
                        }}
                    </div>
                }}
                {if r.requested_by != "" {
                    <p className="mt-2 text-[13px] text-muted-foreground">
                        {"Requested by "}{r.requested_by}
                        {if r.storm_time != "" { <span>{" at "}{r.storm_time}</span> }}
                    </p>
                }}
                {if r.reason != "" {
                    <p className="mt-2 text-[14px] text-muted-foreground">
                        {"Why Ekata sent this to you: "}{r.reason}
                    </p>
                }}
                <div className="mt-4 flex flex-wrap gap-2">
                    {if r.status == "REQUESTED" {
                        <ActionButton
                            label="Accept"
                            busy={busy}
                            onPress={lambda { onAct(r.req_id, "accept"); }}
                        />
                    }}
                    {if r.status == "REQUESTED" {
                        <ActionButton
                            label="Can't help"
                            busy={busy}
                            quiet={True}
                            onPress={lambda { onAct(r.req_id, "decline"); }}
                        />
                    }}
                    {if r.status == "ACCEPTED" {
                        <ActionButton
                            label="Mark on the way"
                            busy={busy}
                            onPress={lambda { onAct(r.req_id, "dispatched"); }}
                        />
                    }}
                    {if r.status == "DISPATCHED" {
                        <ActionButton
                            label="Mark delivered"
                            busy={busy}
                            onPress={lambda { onAct(r.req_id, "delivered"); }}
                        />
                    }}
                    <button
                        type="button"
                        className="min-h-10 px-2 text-[15px] font-semibold text-primary hover:underline"
                        onClick={lambda (e: MouseEvent) { onMap(); }}
                    >
                        Show on map
                    </button>
                </div>
            </div>
        }}
    </article>
}

# ---------- The page ----------

def:pub NgoPortal -> JsxElement {
    has office: str = "";
    has page: str = "requests";
    has groups: list[NgoView] = [];
    has reqs: list[RequestView] = [];
    has loaded: bool = False;
    has busy: bool = False;
    has err: str = "";

    async def refresh -> None {
        try {
            groups = await ngos(int(Date.now()));
            if office != "" {
                reqs = await ngo_requests(office, int(Date.now()));
            }
            err = "";
        } except Exception as ex {
            err = "Could not refresh the list. Trying again shortly.";
        }
        loaded = True;
    }

    async def act(req_id: str, action: str) -> None {
        busy = True;
        try {
            await respond_request(req_id, office, action);
            err = "";
        } except Exception as ex {
            err = "That did not go through. Please try again.";
        }
        await refresh();
        busy = False;
    }

    can with entry {
        office = load_office();
    }

    async can with [office] entry {
        reqs = [];
        await refresh();
    }

    useEffect(
        lambda {
            timer = setInterval(lambda { refresh(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        [office]
    );

    def pick(name: str) -> None {
        save_office(name);
        office = name;
    }

    me: NgoView | None = None;
    for g in groups {
        if g.office == office {
            me = g;
        }
    }
    fresh_reqs = [r for r in reqs if r.status == "REQUESTED" and r.ngo == office];
    done_reqs = [
        r for r in reqs
        if (r.ngo == office and r.status != "REQUESTED")
        or ((office in r.declined_by) and r.ngo != office)
    ];
    fresh_reqs = fresh_reqs[::-1];
    done_reqs = done_reqs[::-1];
    nav = [
        ["requests", "Requests for you", "inbox"],
        ["done", "Accepted and delivered", "truck"],
        ["map", "Map and route", "pin"],
        ["profile", "Your group", "org"]
    ];
    title = "Requests for you";
    subtitle = str(len(fresh_reqs)) + " waiting for an answer";
    if page == "done" {
        title = "Accepted and delivered";
        subtitle = "Requests you took on, and the ones you passed to another group.";
    }
    if page == "map" {
        title = "Map and route";
        subtitle = "Where your requests are, and the best run from your base.";
    }
    if page == "profile" {
        title = "Your group";
        subtitle = "How Ekata sees your group when it picks who to ask.";
    }
    if office == "" {
        subtitle = "Choose your group in the sidebar to see its requests.";
    }

    <AppShell
        tone="ngo"
        tagline="Relief group desk"
        nav={nav}
        active={page}
        onNav={lambda (k: str) { page = k; }}
        title={title}
        subtitle={subtitle}
        workspaceLabel="Your group"
        workspace={
            <WorkspaceSelect
                value={office}
                options={[g.office for g in groups]}
                onPick={pick}
                placeholder="Choose your group"
            />
        }
    >
        {if err != "" {
            <p className="mb-3 text-[15px] text-blocked" role="alert">{err}</p>
        }}
        {if office == "" {
            <Empty
                title="No group chosen yet"
                hint="Pick your relief group from the sidebar. This browser will remember it."
            />
        }}
        {if office != "" and page == "requests" {
            <div className="space-y-3">
                {if loaded and len(fresh_reqs) == 0 {
                    <Empty
                        title="No requests waiting for you"
                        hint="New ones appear here when a division officer asks for help you can give."
                    />
                }}
                {for r in fresh_reqs {
                    <RequestCard
                        key={r.req_id}
                        r={r}
                        office={office}
                        busy={busy}
                        onAct={act}
                        onMap={lambda { page = "map"; }}
                    />
                }}
            </div>
        }}
        {if office != "" and page == "done" {
            <div className="space-y-3">
                {if loaded and len(done_reqs) == 0 {
                    <Empty
                        title="Nothing accepted yet"
                        hint="Requests you accept show up here until they are delivered."
                    />
                }}
                {for r in done_reqs {
                    <RequestCard
                        key={r.req_id}
                        r={r}
                        office={office}
                        busy={busy}
                        onAct={act}
                        onMap={lambda { page = "map"; }}
                    />
                }}
            </div>
        }}
        {if office != "" and page == "map" {
            <NgoMapPage office={office}/>
        }}
        {if office != "" and page == "profile" {
            <Surface title={office}>
                {if me is not None {
                    <div className="grid gap-5 text-[15px] sm:grid-cols-2">
                        <div>
                            <p className="text-[13px] text-muted-foreground">Areas served</p>
                            <p>{", ".join(me.areas) if len(me.areas) > 0 else "Not listed"}</p>
                        </div>
                        <div>
                            <p className="text-[13px] text-muted-foreground">What you offer</p>
                            <p>{", ".join(me.offers) if len(me.offers) > 0 else "Not listed"}</p>
                        </div>
                        <div>
                            <p className="text-[13px] text-muted-foreground">Contact</p>
                            <p>{me.contact if me.contact != "" else "Not listed"}</p>
                        </div>
                        <div>
                            <p className="text-[13px] text-muted-foreground">Open requests</p>
                            <p className="text-[28px] font-semibold leading-tight tabular-nums">{me.open_requests}</p>
                        </div>
                    </div>
                } else {
                    <p className="text-[15px] text-muted-foreground">Loading your group.</p>
                }}
            </Surface>
        }}
    </AppShell>
}
