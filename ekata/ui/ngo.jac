"""Relief group portal: a registered group's coordinator, on a laptop.

Pick the group once, then answer the requests the matcher sent to it:
accept or decline, then mark on the way and delivered.
"""

import from "react" { useEffect }
import from ekata.portal_api { ngos, ngo_requests, respond_request }
import type from ekata.portal { NgoView, RequestView }
import from .atoms {
    PortalHeader, Panel, Empty, RequestBadge, VulnerableBadge, people_label
}

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
        else "min-h-10 rounded-lg bg-primary px-4 text-[15px] font-semibold text-primary-foreground hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
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

# ---------- First visit: choose your group ----------

def:pub GroupPicker(onPick: Callable[[str], None]) -> JsxElement {
    has groups: list[NgoView] = [];
    has loaded: bool = False;
    has err: str = "";

    async can with entry {
        try {
            groups = await ngos(int(Date.now()));
        } except Exception as ex {
            err = "Could not load the list of groups. Refresh the page to try again.";
        }
        loaded = True;
    }

    <main className="mx-auto max-w-[900px] px-6 py-6">
        <h1 className="text-[21px] font-semibold">Which relief group are you?</h1>
        <p className="mt-1 text-[15px] text-muted-foreground">
            Choose once. This browser will remember it.
        </p>
        {if err != "" {
            <p className="mt-3 text-[15px] text-blocked" role="alert">{err}</p>
        }}
        {if loaded and len(groups) == 0 and err == "" {
            <div className="mt-4">
                <Empty
                    title="No relief groups are registered yet"
                    hint="Load the demo data, then refresh."
                />
            </div>
        }}
        <div className="mt-4 grid gap-3 md:grid-cols-2">
            {for g in groups {
                <article key={g.office} className="rounded-lg border border-border bg-card p-4">
                    <p className="text-[17px] font-semibold">{g.office}</p>
                    <p className="mt-1 text-[15px]">
                        {"Areas: "}{", ".join(g.areas) if len(g.areas) > 0 else "not listed"}
                    </p>
                    <p className="text-[15px]">
                        {"Offers: "}{", ".join(g.offers) if len(g.offers) > 0 else "not listed"}
                    </p>
                    <div className="mt-3">
                        <ActionButton
                            label={"Use " + g.office}
                            onPress={lambda { onPick(g.office); }}
                        />
                    </div>
                </article>
            }}
        </div>
    </main>
}

# ---------- One request card ----------

def:pub RequestCard(r: RequestView, office: str, busy: bool, onAct: Callable[[str, str], None]) -> JsxElement {
    mine = r.ngo == office;
    passed = (office in r.declined_by) and not mine;
    <article
        className={
            "rounded-lg border p-4 "
            + (
                "border-border bg-muted"
                if passed
                else ("border-alert/40 bg-alert-soft" if r.status == "REQUESTED" else "border-border bg-card")
            )
        }
    >
        {if passed {
            <p className="text-[15px] text-muted-foreground">
                {r.need}{" at "}{r.place}{". You declined; now with "}{r.ngo if r.ngo != "" else "another group"}{"."}
            </p>
        } else {
            <div>
                <div className="flex flex-wrap items-start justify-between gap-2">
                    <p className="text-[21px] font-semibold leading-tight">{r.need}</p>
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
                    <p className="mt-2 text-[15px]">
                        <span className="font-semibold">{"Why you: "}</span>{r.reason}
                    </p>
                }}
                <div className="mt-3 flex flex-wrap gap-2">
                    {if r.status == "REQUESTED" {
                        <ActionButton
                            label="Accept"
                            busy={busy}
                            onPress={lambda { onAct(r.req_id, "accept"); }}
                        />
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
                </div>
            </div>
        }}
    </article>
}

# ---------- Inbox for one chosen group ----------

def:pub Inbox(office: str) -> JsxElement {
    has reqs: list[RequestView] = [];
    has me: NgoView | None = None;
    has loaded: bool = False;
    has busy: bool = False;
    has err: str = "";

    async def refresh -> None {
        try {
            reqs = await ngo_requests(office, int(Date.now()));
            groups = await ngos(int(Date.now()));
            found: NgoView | None = None;
            for g in groups {
                if g.office == office {
                    found = g;
                }
            }
            me = found;
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

    async can with [office] entry {
        await refresh();
    }

    useEffect(
        lambda {
            timer = setInterval(lambda { refresh(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        [office]
    );

    <main className="mx-auto grid max-w-[1100px] gap-4 px-6 py-4 lg:grid-cols-[1fr_320px]">
        <Panel title="Requests for you" note={str(len(reqs)) + " in your list"}>
            {if err != "" {
                <p className="mb-3 text-[15px] text-blocked" role="alert">{err}</p>
            }}
            {if loaded and len(reqs) == 0 {
                <Empty
                    title="No requests for your group right now"
                    hint="New ones appear here when a division officer asks for help you can give."
                />
            }}
            <div className="space-y-3">
                {for r in reqs {
                    <RequestCard
                        key={r.req_id}
                        r={r}
                        office={office}
                        busy={busy}
                        onAct={act}
                    />
                }}
            </div>
        </Panel>
        <Panel title="Your group">
            {if me is not None {
                <div className="space-y-3 text-[15px]">
                    <div>
                        <p className="text-[13px] text-muted-foreground">Areas served</p>
                        <p>{", ".join(me.areas) if len(me.areas) > 0 else "Not listed"}</p>
                    </div>
                    <div>
                        <p className="text-[13px] text-muted-foreground">What you offer</p>
                        <p>{", ".join(me.offers) if len(me.offers) > 0 else "Not listed"}</p>
                    </div>
                    <div>
                        <p className="text-[13px] text-muted-foreground">Open requests</p>
                        <p className="text-[28px] font-bold leading-tight">{me.open_requests}</p>
                    </div>
                    {if me.contact != "" {
                        <div>
                            <p className="text-[13px] text-muted-foreground">Contact</p>
                            <p>{me.contact}</p>
                        </div>
                    }}
                </div>
            } else {
                <p className="text-[15px] text-muted-foreground">Loading your group.</p>
            }}
        </Panel>
    </main>
}

# ---------- The page ----------

def:pub NgoPortal -> JsxElement {
    has office: str = "";
    has ready: bool = False;

    can with entry {
        office = load_office();
        ready = True;
    }

    def pick(name: str) -> None {
        save_office(name);
        office = name;
    }

    def forget -> None {
        save_office("");
        office = "";
    }

    <div className="min-h-screen bg-background text-foreground">
        <PortalHeader portal="Relief group" who={office}>
            {if office != "" {
                <button
                    type="button"
                    className="min-h-10 rounded-lg px-3 text-[15px] text-primary underline hover:bg-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                    onClick={lambda (e: MouseEvent) { forget(); }}
                >
                    Change group
                </button>
            }}
        </PortalHeader>
        {if ready and office == "" {
            <GroupPicker onPick={pick}/>
        }}
        {if office != "" {
            <Inbox office={office}/>
        }}
    </div>
}
