"""Citizen portal: a person in the flood, usually on a phone.

Four pages inside the shared app shell: send an SOS, track a request, check a
message before sharing or donating, and read official bulletins.
"""

import from "react" { useEffect }
import from ekata.portal_api { citizen_send, track_request, bulletins }
import type from ekata.portal { CitizenStatus, BulletinView }
import from .atoms { Empty, VerdictBadge }
import from .shell { AppShell, WorkspaceSelect, Surface }

glob STAGES: list[str] = [
    "Received",
    "Sent to your division",
    "Officer confirmed",
    "Help is on the way",
    "Help reached you"
];

glob AREAS: list[str] = [
    "Kegalle",
    "Mawanella",
    "Aranayaka",
    "Rambukkana",
    "Warakapola",
    "Yatiyantota",
    "Ratnapura",
    "Kuruwita"
];

glob REF_KEY: str = "ekata.citizen.refs";
glob AREA_KEY: str = "ekata.citizen.area";

glob FOCUS: str = "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#0F4C45]";
glob FIELD: str = "w-full rounded-lg border border-border bg-background text-[16px] " + FOCUS;

def:pub load_refs -> list[str] {
    try {
        raw = localStorage.getItem(REF_KEY);
        if raw is None or raw == "" {
            return [];
        }
        return [p for p in str(raw).split(",") if p != ""];
    } except Exception {
        return [];
    }
}

def:pub save_ref(ref: str) -> list[str] {
    refs = load_refs();
    if ref != "" and ref not in refs {
        refs = [ref] + refs;
        refs = refs[:5];
        try {
            localStorage.setItem(REF_KEY, ",".join(refs));
        } except Exception {
            ok = False;
        }
    }
    return refs;
}

def:pub load_area -> str {
    try {
        raw = localStorage.getItem(AREA_KEY);
        if raw is None {
            return "";
        }
        return str(raw);
    } except Exception {
        return "";
    }
}

def:pub save_area(area: str) -> None {
    try {
        localStorage.setItem(AREA_KEY, area);
    } except Exception {
        ok = False;
    }
}

def:pub BigButton(
    label: str, onPress: Callable[[], None], busy: bool = False, quiet: bool = False
) -> JsxElement {
    cls = (
        "min-h-12 rounded-lg border border-border bg-card px-5 text-[16px] font-semibold text-foreground hover:bg-muted "
        if quiet
        else "min-h-12 rounded-lg bg-[#0F4C45] px-5 text-[16px] font-semibold text-white hover:bg-[#0B3B35] "
    );
    <button
        type="button"
        className={cls + FOCUS + " disabled:opacity-60"}
        disabled={busy}
        onClick={lambda (e: MouseEvent) { onPress(); }}
    >
        {label}
    </button>
}

# ---------- Receipt shown after a request is sent ----------

def:pub Receipt(s: CitizenStatus) -> JsxElement {
    <div className="rounded-lg border border-ok/30 bg-ok-soft p-4" role="status">
        <p className="text-[16px] font-semibold text-ok">We received your message</p>
        <p className="mt-2 text-[14px] text-muted-foreground">Your reference number</p>
        <p className="text-[28px] font-bold leading-tight break-all">{s.msg_id}</p>
        <p className="mt-1 text-[16px]">
            Keep this number. You can use it to see where your request is.
        </p>
    </div>
}

# ---------- Page 1: send an SOS ----------

def:pub SosPage(onSaved: Callable[[str], None], onTrack: Callable[[str], None]) -> JsxElement {
    has text: str = "";
    has busy: bool = False;
    has err: str = "";
    has receipt: CitizenStatus | None = None;
    has last_ref: str = "";

    async def send -> None {
        if text.strip() == "" {
            err = "Please write where you are and what you need.";
            return;
        }
        busy = True;
        err = "";
        try {
            r = await citizen_send(text, "SMS");
            receipt = r;
            last_ref = r.msg_id;
            if r.msg_id != "" {
                onSaved(r.msg_id);
            }
            text = "";
        } except Exception as ex {
            err = "We could not send that. Check your signal and try again.";
        }
        busy = False;
    }

    <div className="mx-auto max-w-[680px] space-y-5">
        <Surface>
            <label htmlFor="sos-text" className="text-[16px] font-medium">
                Where are you, how many people, who cannot move?
            </label>
            <textarea
                id="sos-text"
                rows={5}
                value={text}
                placeholder="Example: Kaduwela, near the bridge. 6 people on the roof, one elderly woman cannot walk."
                className={FIELD + " mt-3 p-3.5"}
                onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
            />
            <p className="mt-2 text-[14px] text-muted-foreground">
                You can write in Sinhala, Tamil or English.
            </p>
            {if err != "" {
                <p className="mt-3 text-[16px] text-blocked" role="alert">{err}</p>
            }}
            <div className="mt-5">
                <BigButton
                    label={"Sending..." if busy else "Send for help"}
                    busy={busy}
                    onPress={lambda { send(); }}
                />
            </div>
        </Surface>
        {if receipt is not None {
            <Surface>
                <Receipt s={receipt}/>
                <div className="mt-4">
                    <BigButton
                        label="Track this request"
                        onPress={lambda { onTrack(last_ref); }}
                    />
                </div>
            </Surface>
        }}
        <p className="rounded-xl border border-alert/30 bg-alert-soft px-5 py-4 text-[15px]">
            In danger now? Call 117 (Disaster Management Centre) or 119 (Police).
        </p>
    </div>
}

# ---------- Page 2: track a request ----------

def:pub Stepper(stage: int) -> JsxElement {
    <ol className="mt-4 space-y-3">
        {for i in range(len(STAGES)) {
            <li key={i} className="flex items-center gap-3">
                <span
                    className={
                        "flex size-8 shrink-0 items-center justify-center rounded-full border text-[15px] font-bold "
                        + (
                            "border-[#0F4C45] bg-[#0F4C45] text-white"
                            if i <= stage
                            else "border-border bg-muted text-muted-foreground"
                        )
                    }
                >
                    {i + 1}
                </span>
                <span
                    className={
                        "text-[16px] "
                        + (
                            "font-semibold text-foreground"
                            if i == stage
                            else ("text-foreground" if i < stage else "text-muted-foreground")
                        )
                    }
                >
                    {STAGES[i]}
                    {if i == stage {
                        <span className="ml-2 text-[14px] font-normal text-muted-foreground">
                            Now
                        </span>
                    }}
                </span>
            </li>
        }}
    </ol>
}

def:pub TrackPage(refs: list[str], preset: str, presetNonce: int) -> JsxElement {
    has field: str = "";
    has active: str = "";
    has status: CitizenStatus | None = None;
    has busy: bool = False;
    has err: str = "";

    async def fetch_status(ref: str) -> None {
        try {
            r = await track_request(ref, int(Date.now()));
            status = r;
            err = "";
        } except Exception as ex {
            err = "We could not reach the desk. Check your signal and try again.";
        }
    }

    async def start(ref: str) -> None {
        cleaned = ref.strip();
        if cleaned == "" {
            err = "Type your reference number first.";
            return;
        }
        busy = True;
        active = cleaned;
        field = cleaned;
        await fetch_status(cleaned);
        busy = False;
    }

    async can with [presetNonce] entry {
        if preset != "" {
            await start(preset);
        }
    }

    useEffect(
        lambda {
            timer = setInterval(
                lambda {
                    if active != "" {
                        fetch_status(active);
                    }
                },
                10000
            );
            return lambda { clearInterval(timer); };
        },
        [active]
    );

    <div className="mx-auto max-w-[680px] space-y-5">
        <Surface>
            <label htmlFor="track-ref" className="text-[16px] font-medium">Reference number</label>
            <div className="mt-3 flex gap-2">
                <input
                    id="track-ref"
                    type="text"
                    value={field}
                    className={FIELD + " min-h-12 min-w-0 flex-1 px-3.5"}
                    onChange={lambda (e: ChangeEvent) { field = e.target.value; }}
                />
                <BigButton
                    label="Check"
                    busy={busy}
                    onPress={lambda { start(field); }}
                />
            </div>
            {if len(refs) > 0 {
                <div className="mt-5">
                    <p className="text-[14px] text-muted-foreground">Your requests</p>
                    <div className="mt-2 flex flex-wrap gap-2">
                        {for r in refs {
                            <button
                                key={r}
                                type="button"
                                className={"min-h-12 rounded-lg border border-border bg-card px-4 text-[16px] font-semibold hover:bg-muted " + FOCUS}
                                onClick={lambda (e: MouseEvent) { start(r); }}
                            >
                                {r}
                            </button>
                        }}
                    </div>
                </div>
            }}
            {if err != "" {
                <p className="mt-4 text-[16px] text-blocked" role="alert">{err}</p>
            }}
        </Surface>
        {if status is not None {
            <Surface>
                {if not status.found {
                    <Empty
                        title="We cannot find that number"
                        hint="Check the number and try again. It may take a moment to appear."
                    />
                } else {
                    <div>
                        <p className="text-[18px] font-semibold">{status.stage_label}</p>
                        {if status.detail != "" {
                            <p className="mt-1 text-[16px]">{status.detail}</p>
                        }}
                        <Stepper stage={status.stage}/>
                        {if status.ds != "" or status.officer != "" {
                            <p className="mt-5 text-[16px]">
                                {if status.ds != "" {
                                    <span>{"Division: "}{status.ds}{". "}</span>
                                }}
                                {if status.officer != "" {
                                    <span>{"Officer: "}{status.officer}{"."}</span>
                                }}
                            </p>
                        }}
                        {if len(status.help) > 0 {
                            <div className="mt-5">
                                <p className="text-[14px] text-muted-foreground">Help arranged</p>
                                <ul className="mt-2 space-y-2">
                                    {for h in status.help {
                                        <li
                                            key={h}
                                            className="rounded-lg border border-border bg-muted px-3.5 py-2.5 text-[16px]"
                                        >
                                            {h}
                                        </li>
                                    }}
                                </ul>
                            </div>
                        }}
                        <p className="mt-5 text-[14px] text-muted-foreground">
                            This page refreshes every 10 seconds.
                        </p>
                    </div>
                }}
            </Surface>
        }}
    </div>
}

# ---------- Page 3: check a message ----------

def:pub CheckPage(onSaved: Callable[[str], None], onTrack: Callable[[str], None]) -> JsxElement {
    has text: str = "";
    has busy: bool = False;
    has err: str = "";
    has result: CitizenStatus | None = None;
    has last_ref: str = "";

    async def check -> None {
        if text.strip() == "" {
            err = "Paste the message you want checked.";
            return;
        }
        busy = True;
        err = "";
        result = None;
        try {
            r = await citizen_send(text, "WHATSAPP");
            result = r;
            last_ref = r.msg_id;
            if r.kind == "SOS" and r.msg_id != "" {
                onSaved(r.msg_id);
            }
        } except Exception as ex {
            err = "We could not check that. Try again in a moment.";
        }
        busy = False;
    }

    <div className="mx-auto max-w-[680px] space-y-5">
        <Surface>
            <label htmlFor="check-text" className="text-[16px] font-medium">
                Paste an appeal or forwarded message
            </label>
            <textarea
                id="check-text"
                rows={5}
                value={text}
                className={FIELD + " mt-3 p-3.5"}
                onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
            />
            {if err != "" {
                <p className="mt-3 text-[16px] text-blocked" role="alert">{err}</p>
            }}
            <div className="mt-5">
                <BigButton
                    label={"Checking..." if busy else "Check this message"}
                    busy={busy}
                    onPress={lambda { check(); }}
                />
            </div>
        </Surface>
        {if result is not None {
            <Surface>
                <div role="status">
                    {if result.kind == "SOS" {
                        <div>
                            <p className="mb-4 text-[16px]">
                                This reads like a request for help, so we sent it to the desk.
                            </p>
                            <Receipt s={result}/>
                            <div className="mt-4">
                                <BigButton
                                    label="Track this request"
                                    onPress={lambda { onTrack(last_ref); }}
                                />
                            </div>
                        </div>
                    } else {
                        <div>
                            {if result.kind == "APPEAL" or result.kind == "RUMOUR" {
                                <div>
                                    <VerdictBadge verdict={result.verdict}/>
                                    {if result.verdict_reason != "" {
                                        <p className="mt-3 text-[16px]">{result.verdict_reason}</p>
                                    }}
                                    <p className="mt-3 text-[16px] font-semibold">
                                        Do not send money or OTP codes. Pass it on only if an official bulletin says the same.
                                    </p>
                                </div>
                            } else {
                                <p className="text-[16px]">
                                    We did not find anything to check in this message. If you need help, use Send an SOS.
                                </p>
                            }}
                        </div>
                    }}
                </div>
            </Surface>
        }}
    </div>
}

# ---------- Page 4: official bulletins ----------

def:pub BulletinPage(area: str) -> JsxElement {
    has items: list[BulletinView] = [];
    has loaded: bool = False;
    has err: str = "";

    async def load -> None {
        try {
            items = await bulletins(area, int(Date.now()));
            err = "";
        } except Exception as ex {
            err = "Bulletins are not available right now.";
        }
        loaded = True;
    }

    async can with [area] entry {
        await load();
    }

    <div className="mx-auto max-w-[680px] space-y-5">
        <p className="text-[15px] text-muted-foreground">
            {"Showing bulletins for " + area if area != "" else "Showing bulletins for every area. Choose your area on the left to narrow them."}
        </p>
        {if err != "" {
            <p className="text-[16px] text-blocked" role="alert">{err}</p>
        }}
        {if loaded and len(items) == 0 and err == "" {
            <Surface>
                <Empty title="No bulletins for this area yet" hint="Check again later."/>
            </Surface>
        }}
        {for b in items {
            <article
                key={b.issuer + b.issued_at + b.text[:20]}
                className="rounded-xl border border-border bg-card p-5"
            >
                <p className="text-[16px] font-semibold">{b.issuer}</p>
                <p className="text-[14px] text-muted-foreground">
                    {b.area}{if b.issued_at != "" { <span>{", "}{b.issued_at}</span> }}
                </p>
                <p className="mt-3 whitespace-pre-wrap break-words text-[16px] leading-relaxed">{b.text}</p>
            </article>
        }}
    </div>
}

# ---------- The portal ----------

def:pub CitizenPortal -> JsxElement {
    has refs: list[str] = [];
    has preset: str = "";
    has nonce: int = 0;
    has page: str = "sos";
    has area: str = "";

    can with entry {
        refs = load_refs();
        area = load_area();
    }

    def saved(ref: str) -> None {
        refs = save_ref(ref);
    }

    def track(ref: str) -> None {
        preset = ref;
        nonce = nonce + 1;
        page = "track";
    }

    def pick_area(v: str) -> None {
        area = v;
        save_area(v);
    }

    nav = [
        ["sos", "Send an SOS", "sos"],
        ["track", "Track my request", "track"],
        ["check", "Check a message", "check"],
        ["bulletins", "Official bulletins", "bulletin"]
    ];
    titles = {
        "sos": ["Send an SOS", "Tell us where you are and who needs help. A division officer will call you."],
        "track": ["Track my request", "Enter your reference number to see where your request is."],
        "check": ["Check a message", "Paste an appeal or forwarded message before you share it or send money."],
        "bulletins": ["Official bulletins", "Warnings and notices from the authorities for your area."]
    };
    head = titles[page];

    <AppShell
        tone="citizen"
        tagline="Help on a flood night"
        nav={nav}
        active={page}
        onNav={lambda (k: str) { page = k; }}
        title={head[0]}
        subtitle={head[1]}
        workspaceLabel="Your area"
        workspace={<WorkspaceSelect value={area} options={AREAS} onPick={pick_area} placeholder="Choose your area"/>}
    >
        {if page == "sos" {
            <SosPage onSaved={saved} onTrack={track}/>
        }}
        {if page == "track" {
            <TrackPage refs={refs} preset={preset} presetNonce={nonce}/>
        }}
        {if page == "check" {
            <CheckPage onSaved={saved} onTrack={track}/>
        }}
        {if page == "bulletins" {
            <BulletinPage area={area}/>
        }}
    </AppShell>
}
