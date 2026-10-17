"""District portal: registry of offices and groups, and the bulletin desk."""
import from "react" { useEffect }
import type from ekata.portal { NgoView, BulletinView, DivisionView }
import from ekata.portal_api { registry, bulletins, publish_bulletin, divisions }
import from ...components.ui.button { Button }
import from .atoms { Empty }

def:pub RegistryTab -> JsxElement {
    has offices: list[NgoView] = [];
    has posted: list[BulletinView] = [];
    has places: list[str] = ["Kegalle", "Ratnapura"];
    has tick: int = 0;
    has issuer: str = "DMC";
    has area: str = "Kegalle";
    has text: str = "";
    has busy: bool = False;
    has error: str = "";
    has note: str = "";

    async def refresh -> None {
        try {
            tick = tick + 1;
            offices = await registry(tick);
            posted = await bulletins("", tick);
            divs = await divisions(tick);
            names: list[str] = ["Kegalle", "Ratnapura"];
            for d in divs {
                if d.ds not in names {
                    names = names + [d.ds];
                }
            }
            places = names;
        } except Exception as e {
            error = "Could not load the registry. It will retry.";
        }
    }
    async def publish -> None {
        if text.strip() == "" {
            error = "Write the bulletin text first.";
            return;
        }
        busy = True;
        try {
            await publish_bulletin(issuer, area, text.strip());
            text = "";
            error = "";
            note = "Bulletin published.";
            await refresh();
        } except Exception as e {
            error = "The bulletin was not published: " + str(e);
        }
        busy = False;
    }
    async can with entry {
        await refresh();
    }
    useEffect(
        lambda {
            timer = setInterval(lambda { refresh(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        []
    );

    <section aria-label="Registry and bulletins" className="grid gap-8 lg:grid-cols-[3fr_2fr]">
        <div className="min-w-0">
            <h2 className="mb-2 text-[17px] font-semibold">Offices and relief groups</h2>
            {if len(offices) == 0 {
                <Empty title="No registered offices yet"/>
            }}
            {if len(offices) > 0 {
                <div className="overflow-x-auto border-y border-border">
                    <table className="w-full text-left text-[15px]">
                        <thead>
                            <tr className="border-b border-border text-[13px] text-muted-foreground">
                                <th className="py-2 pr-4 font-semibold">Name</th>
                                <th className="py-2 pr-4 font-semibold">Contact</th>
                                <th className="py-2 pr-4 font-semibold">Areas</th>
                                <th className="py-2 pr-4 font-semibold">Offers</th>
                                <th className="py-2 font-semibold">Open requests</th>
                            </tr>
                        </thead>
                        <tbody>
                            {for o in offices {
                                <tr key={o.office} className="border-b border-border align-top last:border-0">
                                    <td className="py-2 pr-4 font-semibold">{o.office}</td>
                                    <td className="py-2 pr-4">{o.contact}</td>
                                    <td className="py-2 pr-4">{", ".join(o.areas)}</td>
                                    <td className="py-2 pr-4">{", ".join(o.offers)}</td>
                                    <td className="py-2 tabular-nums">{o.open_requests}</td>
                                </tr>
                            }}
                        </tbody>
                    </table>
                </div>
            }}
        </div>
        <div className="min-w-0">
            <h2 className="mb-2 text-[17px] font-semibold">Publish a bulletin</h2>
            <form
                className="space-y-3"
                onSubmit={lambda (e: FormEvent) { e.preventDefault(); publish(); }}
            >
                <div className="grid grid-cols-2 gap-3">
                    <label className="block text-[13px] font-semibold">
                        {"Issued by"}
                        <select
                            className="mt-1 w-full rounded-md border border-input bg-card px-2 py-2 text-[15px] font-normal focus-visible:outline-2 focus-visible:outline-primary"
                            value={issuer}
                            onChange={lambda (e: ChangeEvent) { issuer = e.target.value; }}
                        >
                            <option>DMC</option>
                            <option>NBRO</option>
                            <option>Irrigation</option>
                            <option>District Secretariat</option>
                        </select>
                    </label>
                    <label className="block text-[13px] font-semibold">
                        {"Area"}
                        <select
                            className="mt-1 w-full rounded-md border border-input bg-card px-2 py-2 text-[15px] font-normal focus-visible:outline-2 focus-visible:outline-primary"
                            value={area}
                            onChange={lambda (e: ChangeEvent) { area = e.target.value; }}
                        >
                            {for p in places {
                                <option key={p}>{p}</option>
                            }}
                        </select>
                    </label>
                </div>
                <label className="block text-[13px] font-semibold">
                    {"Bulletin text"}
                    <textarea
                        rows={4}
                        className="mt-1 w-full rounded-md border border-input bg-card px-3 py-2 text-[15px] font-normal focus-visible:outline-2 focus-visible:outline-primary"
                        value={text}
                        onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
                    />
                </label>
                <div className="flex items-center gap-3">
                    <Button type="submit" disabled={busy}>Publish bulletin</Button>
                    {if note != "" and error == "" {
                        <span role="status" className="text-[13px] text-ok">{note}</span>
                    }}
                </div>
                {if error != "" {
                    <p role="alert" className="text-[13px] text-blocked">{error}</p>
                }}
            </form>
            <h3 className="mb-1 mt-6 text-[15px] font-semibold">Published bulletins</h3>
            {if len(posted) == 0 {
                <p className="text-[13px] text-muted-foreground">Nothing published yet.</p>
            }}
            <ul className="divide-y divide-border border-y border-border">
                {for b in posted {
                    <li key={b.issuer + b.issued_at + b.text} className="py-3">
                        <p className="text-[13px] text-muted-foreground">
                            {b.issued_at + ", " + b.issuer + " for " + b.area}
                        </p>
                        <p className="mt-0.5 text-[15px]">{b.text}</p>
                    </li>
                }}
            </ul>
        </div>
    </section>
}
