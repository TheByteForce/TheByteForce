"""Officer: the GN household register. Everyone in one Grama Niladhari division,
read beside tonight's messages; vulnerable households not heard from come first."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { UserGroupIcon, Call02Icon, Alert02Icon, Location01Icon }
import type from crisisconnect.gn_register { GnChoice, GnRegisterView, HouseholdRow }
import from crisisconnect.gn_register_api { gn_areas, gn_register, setup_gn_register, open_gn_register }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.native_select { NativeSelectOption }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { Tag, StatusTag, VulnerableTag }
import from ...components.app.labels { plural }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, SelectField }

def:pub HouseholdCard(row: HouseholdRow) -> JsxElement {
    <Card className={"border-red-200 bg-red-50/40" if row.group == 0 else ""}>
        <CardHeader>
            <div className="flex flex-wrap items-center gap-2">
                <Tag label={row.action} tone={row.tone} />
                {if row.status != "" {
                    <StatusTag status={row.status} />
                }}
                {for v in row.vulnerable {
                    <VulnerableTag key={v} flag={v} />
                }}
                {if row.evac_help {
                    <Tag label="Needs help to evacuate" tone="red" />
                }}
            </div>
            <CardTitle className="text-lg leading-snug">{row.address}</CardTitle>
            <CardDescription>{row.hh_id + " · " + plural(row.people, "person", "people") + (" · " + row.phone if row.phone != "" else "")}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
            {if row.note != "" {
                <p className="text-muted-foreground">{row.note}</p>
            }}
            <ul className="flex flex-col gap-1">
                {for r in row.residents {
                    <li key={r.name} className="flex flex-wrap items-center gap-2">
                        <span className="font-medium">{r.name}</span>
                        <span className="text-muted-foreground">{(f"{r.age} yrs" if r.age > 0 else "baby")}</span>
                        {for n in r.needs {
                            <Tag key={n} label={n} tone="amber" />
                        }}
                        {if r.note != "" {
                            <span className="text-muted-foreground">{r.note}</span>
                        }}
                    </li>
                }}
            </ul>
            {if row.heard {
                <div className="flex flex-col gap-1">
                    <p className="inline-flex items-center gap-1 font-medium">
                        <HugeiconsIcon icon={Call02Icon} strokeWidth={2} className="size-4" />
                        {"Heard from tonight, last at " + row.last_heard}
                    </p>
                    <ul className="flex flex-col gap-0.5 text-muted-foreground">
                        {for l in row.links {
                            <li key={l}>{l}</li>
                        }}
                    </ul>
                </div>
            }}
            {if len(row.inc_ids) > 0 {
                <div className="flex flex-wrap items-center gap-2">
                    <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-4 text-muted-foreground" />
                    {for i in row.inc_ids {
                        <Link key={i} to={"/officer/cases/" + i} className="font-medium underline underline-offset-2">{"Open " + i}</Link>
                    }}
                </div>
            }}
            {if row.verified_call != "" {
                <p><span className="font-medium">Verified call: </span>{row.verified_call}</p>
            }}
            {if len(row.relief) > 0 {
                <div className="flex flex-wrap gap-2">
                    {for x in row.relief {
                        <Tag key={x} label={"Relief " + x} tone="violet" />
                    }}
                </div>
            }}
            {if len(row.possible) > 0 {
                <div className="flex flex-col gap-1 rounded-lg border border-dashed pt-2 pb-2 pl-3 pr-3">
                    <p className="inline-flex items-center gap-1 font-medium">
                        <HugeiconsIcon icon={Alert02Icon} strokeWidth={2} className="size-4" />
                        Possible match, not linked
                    </p>
                    <ul className="flex flex-col gap-0.5 text-muted-foreground">
                        {for p in row.possible {
                            <li key={p}>{p}</li>
                        }}
                    </ul>
                </div>
            }}
        </CardContent>
    </Card>
}

def:pub GnRegisterPage -> JsxPage {
    ctx: any = use_desk();
    has areas: list[GnChoice] = [];
    has gn: str = "";
    has view: GnRegisterView | None = None;
    has loaded: bool = False;
    has tried_setup: bool = False;

    async can with (ctx.tick, gn) entry {
        got: list[GnChoice] = [];
        pick: str = gn;
        matched: bool = False;
        try {
            got = await gn_areas(ctx.tick);
            if len(got) == 0 and not tried_setup {
                tried_setup = True;
                await setup_gn_register();
                got = await gn_areas(ctx.tick + 1);
            }
            areas = got;
            if pick == "" and len(got) > 0 {
                pick = got[0].gn;
                for a in got {
                    if not matched and ctx.ds != "" and a.ds.lower() == ctx.ds.lower() {
                        pick = a.gn;
                        matched = True;
                    }
                }
                gn = pick;
            } elif pick != "" {
                view = await gn_register(pick, ctx.tick);
            }
        } except Exception as ex {
            view = None;
        }
        loaded = True;
    }

    async def pick_gn(v: str) -> None {
        gn = v;
        try {
            await open_gn_register(v, "");
        } except Exception as ex {
            loaded = True;
        }
    }

    households_n: int = view.households if view else 0;
    heard_n: int = view.heard if view else 0;
    check_n: int = view.check_now if view else 0;
    rows: list[HouseholdRow] = view.rows if view else [];
    note: str = view.note if view else "";

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Grama Niladhari register · " + (gn if gn != "" else "choose a GN division")}
            title="Everyone in your GN division."
            description="Registered households read beside tonight's messages. Vulnerable people nobody has heard from come first, so you can check on them before they have to ask."
            image="/static/assets/images/operations-center.jpg"
            imageAlt="Operators at their desks in an emergency operations centre"
            capsules={[
                [plural(households_n, "household", "households"), "blue"],
                [f"{heard_n} heard from tonight", "green"],
                [f"{check_n} to check on now", "red"]
            ]}
        />
        <div className="flex flex-wrap items-center gap-3 rounded-xl border bg-card pt-3 pb-3 pl-4 pr-4">
            <label htmlFor="gn-pick" className="text-sm text-muted-foreground">GN division</label>
            <SelectField id="gn-pick" value={gn} className="min-w-56" onChange={lambda (e: ChangeEvent) { pick_gn(e.target.value); }}>
                {for a in areas {
                    <NativeSelectOption key={a.gn} value={a.gn}>{a.gn + " · " + a.ds + " DS · " + plural(a.households, "household", "households")}</NativeSelectOption>
                }}
            </SelectField>
            <span className="text-xs text-muted-foreground">Synthetic register. Opening a division is logged.</span>
        </div>
        {if not loaded {
            <LoadingRows count={4} className="h-28" />
        } elif len(areas) == 0 {
            <EmptyNote
                title="The register is not set up yet"
                description="Load the demo data to set up the synthetic household register."
                icon={UserGroupIcon}
            />
        } elif len(rows) == 0 {
            <EmptyNote title={"No households registered in " + gn} description={note} icon={UserGroupIcon} />
        } else {
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {for r in rows {
                    <HouseholdCard key={r.hh_id} row={r} />
                }}
            </div>
            if note != "" {
                <p className="text-xs text-muted-foreground">{note}</p>
            }
        }}
    </div>
}
