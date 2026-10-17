"""Citizen portal: a person in the flood, usually on a phone.

Four plain sections: send an SOS, track a request, check a message before
sharing or donating, and read official bulletins.
"""

import from "react" { useEffect }
import from ekata.portal_api { citizen_send, track_request, bulletins }
import type from ekata.portal { CitizenStatus, BulletinView }
import from .atoms { PortalHeader, Panel, Empty, VerdictBadge }

glob STAGES: list[str] = [
    "Received",
    "Sent to your division",
    "Officer confirmed",
    "Help is on the way",
    "Help reached you"
];

glob REF_KEY: str = "ekata.citizen.refs";

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

def:pub BigButton(
    label: str, onPress: Callable[[], None], busy: bool = False, quiet: bool = False
) -> JsxElement {
    cls = (
        "min-h-12 rounded-lg border border-border bg-card px-5 text-[15px] font-semibold text-foreground hover:bg-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        if quiet
        else "min-h-12 rounded-lg bg-primary px-5 text-[15px] font-semibold text-primary-foreground hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
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

# ---------- Receipt shown after a request is sent ----------

def:pub Receipt(s: CitizenStatus) -> JsxElement {
    <div className="mt-3 rounded-lg border border-ok/30 bg-ok-soft p-4" role="status">
        <p className="text-[15px] font-semibold text-ok">We received your message</p>
        <p className="mt-2 text-[13px] text-muted-foreground">Your reference number</p>
        <p className="text-[28px] font-bold leading-tight break-all">{s.msg_id}</p>
        <p className="mt-1 text-[15px]">
            Keep this number. You can use it below to see where your request is.
        </p>
    </div>
}

# ---------- Section 1: send an SOS ----------

def:pub SosSection(onSaved: Callable[[str], None]) -> JsxElement {
    has text: str = "";
    has busy: bool = False;
    has err: str = "";
    has receipt: CitizenStatus | None = None;

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
            if r.msg_id != "" {
                onSaved(r.msg_id);
            }
            text = "";
        } except Exception as ex {
            err = "We could not send that. Check your signal and try again.";
        }
        busy = False;
    }

    <Panel title="Send an SOS">
        <label htmlFor="sos-text" className="text-[15px]">
            Where are you, how many people, who cannot move?
        </label>
        <textarea
            id="sos-text"
            rows={5}
            value={text}
            placeholder="Example: Kaduwela, near the bridge. 6 people on the roof, one elderly woman cannot walk."
            className="mt-2 w-full rounded-lg border border-border bg-background p-3 text-[15px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
        />
        <p className="mt-1 text-[13px] text-muted-foreground">
            You can write in Sinhala, Tamil or English.
        </p>
        {if err != "" {
            <p className="mt-2 text-[15px] text-blocked" role="alert">{err}</p>
        }}
        <div className="mt-3">
            <BigButton
                label={"Sending..." if busy else "Send for help"}
                busy={busy}
                onPress={lambda { send(); }}
            />
        </div>
        {if receipt is not None {
            <Receipt s={receipt}/>
        }}
        <p className="mt-4 rounded-lg border border-alert/40 bg-alert-soft p-3 text-[15px]">
            In danger now? Call 117 (Disaster Management Centre) or 119 (Police).
        </p>
    </Panel>
}

# ---------- Section 2: track a request ----------

def:pub Stepper(stage: int) -> JsxElement {
    <ol className="mt-3 space-y-2">
        {for i in range(len(STAGES)) {
            <li key={i} className="flex items-center gap-3">
                <span
                    className={
                        "flex size-8 shrink-0 items-center justify-center rounded-full border text-[15px] font-bold "
                        + (
                            "border-primary bg-primary text-primary-foreground"
                            if i <= stage
                            else "border-border bg-muted text-muted-foreground"
                        )
                    }
                >
                    {i + 1}
                </span>
                <span
                    className={
                        "text-[15px] "
                        + (
                            "font-semibold text-foreground"
                            if i == stage
                            else ("text-foreground" if i < stage else "text-muted-foreground")
                        )
                    }
                >
                    {STAGES[i]}
                    {if i == stage {
                        <span className="ml-2 text-[13px] font-normal text-muted-foreground">
                            Now
                        </span>
                    }}
                </span>
            </li>
        }}
    </ol>
}

def:pub TrackSection(refs: list[str], preset: str, presetNonce: int) -> JsxElement {
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

    <Panel title="Track my request">
        <label htmlFor="track-ref" className="text-[15px]">Reference number</label>
        <div className="mt-2 flex gap-2">
            <input
                id="track-ref"
                type="text"
                value={field}
                className="min-h-12 min-w-0 flex-1 rounded-lg border border-border bg-background px-3 text-[15px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                onChange={lambda (e: ChangeEvent) { field = e.target.value; }}
            />
            <BigButton
                label="Check"
                busy={busy}
                onPress={lambda { start(field); }}
            />
        </div>
        {if len(refs) > 0 {
            <div className="mt-3">
                <p className="text-[13px] text-muted-foreground">Your requests</p>
                <div className="mt-1 flex flex-wrap gap-2">
                    {for r in refs {
                        <button
                            key={r}
                            type="button"
                            className="min-h-12 rounded-lg border border-border bg-card px-4 text-[15px] font-semibold hover:bg-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                            onClick={lambda (e: MouseEvent) { start(r); }}
                        >
                            {r}
                        </button>
                    }}
                </div>
            </div>
        }}
        {if err != "" {
            <p className="mt-3 text-[15px] text-blocked" role="alert">{err}</p>
        }}
        {if status is not None {
            <div className="mt-4">
                {if not status.found {
                    <Empty
                        title="We cannot find that number"
                        hint="Check the number and try again. It may take a moment to appear."
                    />
                } else {
                    <div>
                        <p className="text-[17px] font-semibold">{status.stage_label}</p>
                        {if status.detail != "" {
                            <p className="mt-1 text-[15px]">{status.detail}</p>
                        }}
                        <Stepper stage={status.stage}/>
                        {if status.ds != "" or status.officer != "" {
                            <p className="mt-3 text-[15px]">
                                {if status.ds != "" {
                                    <span>{"Division: "}{status.ds}{". "}</span>
                                }}
                                {if status.officer != "" {
                                    <span>{"Officer: "}{status.officer}{"."}</span>
                                }}
                            </p>
                        }}
                        {if len(status.help) > 0 {
                            <div className="mt-3">
                                <p className="text-[13px] text-muted-foreground">Help arranged</p>
                                <ul className="mt-1 space-y-1">
                                    {for h in status.help {
                                        <li
                                            key={h}
                                            className="rounded-md border border-border bg-muted px-3 py-2 text-[15px]"
                                        >
                                            {h}
                                        </li>
                                    }}
                                </ul>
                            </div>
                        }}
                        <p className="mt-3 text-[13px] text-muted-foreground">
                            This page refreshes every 10 seconds.
                        </p>
                    </div>
                }}
            </div>
        }}
    </Panel>
}

# ---------- Section 3: check a message ----------

def:pub CheckSection(onSaved: Callable[[str], None]) -> JsxElement {
    has text: str = "";
    has busy: bool = False;
    has err: str = "";
    has result: CitizenStatus | None = None;

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
            if r.kind == "SOS" and r.msg_id != "" {
                onSaved(r.msg_id);
            }
        } except Exception as ex {
            err = "We could not check that. Try again in a moment.";
        }
        busy = False;
    }

    <Panel title="Check a message before you share or donate">
        <label htmlFor="check-text" className="text-[15px]">
            Paste an appeal or forwarded message
        </label>
        <textarea
            id="check-text"
            rows={4}
            value={text}
            className="mt-2 w-full rounded-lg border border-border bg-background p-3 text-[15px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
        />
        {if err != "" {
            <p className="mt-2 text-[15px] text-blocked" role="alert">{err}</p>
        }}
        <div className="mt-3">
            <BigButton
                label={"Checking..." if busy else "Check this message"}
                busy={busy}
                quiet={True}
                onPress={lambda { check(); }}
            />
        </div>
        {if result is not None {
            <div className="mt-4" role="status">
                {if result.kind == "SOS" {
                    <div>
                        <p className="text-[15px]">
                            This reads like a request for help, so we sent it to the desk.
                        </p>
                        <Receipt s={result}/>
                    </div>
                } else {
                    <div className="rounded-lg border border-border bg-card p-3">
                        {if result.kind == "APPEAL" or result.kind == "RUMOUR" {
                            <div>
                                <VerdictBadge verdict={result.verdict}/>
                                {if result.verdict_reason != "" {
                                    <p className="mt-2 text-[15px]">{result.verdict_reason}</p>
                                }}
                                <p className="mt-2 text-[15px] font-semibold">
                                    Do not send money or OTP codes. Pass it on only if an official bulletin below says the same.
                                </p>
                            </div>
                        } else {
                            <p className="text-[15px]">
                                We did not find anything to check in this message. If you need help, use Send an SOS.
                            </p>
                        }}
                    </div>
                }}
            </div>
        }}
    </Panel>
}

# ---------- Section 4: official bulletins ----------

def:pub BulletinSection() -> JsxElement {
    has area: str = "";
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

    <Panel title="Official bulletins">
        <label htmlFor="bulletin-area" className="text-[15px]">Show bulletins for your area</label>
        <input
            id="bulletin-area"
            type="text"
            value={area}
            placeholder="Example: Kaduwela"
            className="mt-2 min-h-12 w-full rounded-lg border border-border bg-background px-3 text-[15px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            onChange={lambda (e: ChangeEvent) { area = e.target.value; }}
        />
        {if err != "" {
            <p className="mt-2 text-[15px] text-blocked" role="alert">{err}</p>
        }}
        <div className="mt-3 space-y-2">
            {if loaded and len(items) == 0 and err == "" {
                <Empty title="No bulletins for this area yet" hint="Check again later."/>
            }}
            {for b in items {
                <article
                    key={b.issuer + b.issued_at + b.text[:20]}
                    className="rounded-lg border border-border bg-card p-3"
                >
                    <p className="text-[15px] font-semibold">{b.issuer}</p>
                    <p className="text-[13px] text-muted-foreground">
                        {b.area}{if b.issued_at != "" { <span>{", "}{b.issued_at}</span> }}
                    </p>
                    <p className="mt-2 whitespace-pre-wrap break-words text-[15px]">{b.text}</p>
                </article>
            }}
        </div>
    </Panel>
}

# ---------- The page ----------

def:pub CitizenPortal -> JsxElement {
    has refs: list[str] = [];
    has preset: str = "";
    has nonce: int = 0;

    can with entry {
        refs = load_refs();
    }

    def saved(ref: str) -> None {
        refs = save_ref(ref);
        preset = ref;
        nonce = nonce + 1;
    }

    <div className="min-h-screen bg-background text-foreground">
        <PortalHeader portal="I need help"/>
        <main className="mx-auto max-w-[640px] space-y-4 px-4 py-4">
            <SosSection onSaved={saved}/>
            <TrackSection refs={refs} preset={preset} presetNonce={nonce}/>
            <CheckSection onSaved={saved}/>
            <BulletinSection/>
        </main>
    </div>
}
