"""DS hand-over: pick a Divisional Secretariat division to open its sheet."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { File01Icon, ArrowRight01Icon }
import type from ekata.ds_sheet { DsCount }
import from ekata.coordination_api { ds_divisions }
import from ....components.app.desk_state { use_desk }
import from ....components.app.labels { plural }
import from ....components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }

def:pub HandoverIndex -> JsxPage {
    ctx: any = use_desk();
    has rows: list[DsCount] = [];
    has loaded: bool = False;

    async def load(t: int) -> None {
        try {
            rows = await ds_divisions(t);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    async can with [ctx.tick] entry {
        await load(ctx.tick);
    }

    confirmed_n: int = sum([d.confirmed for d in rows]);
    open_n: int = sum([d.open_count for d in rows]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District · DS hand-over"
            title="Clean sheets for DS officers."
            description="Phone-verified incidents for each Divisional Secretariat division, ready to hand to DS and GN officers. Pick a division to open its sheet."
            image="/static/assets/images/officials-meeting.jpg"
            imageAlt="Officials around a table at an emergency operations centre"
            capsules={[
                [plural(len(rows), "division", "divisions"), "blue"],
                [f"{confirmed_n} confirmed", "green"],
                [f"{open_n} open", "amber"]
            ]}
        />
        {if not loaded {
            <LoadingRows count={3} className="h-20" />
        } elif len(rows) == 0 {
            <EmptyNote
                title="No divisions yet"
                description="Divisions appear once incidents are placed in a DS division."
                icon={File01Icon}
            />
        } else {
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {for d in rows {
                    <Link
                        key={d.ds}
                        to={"/district/handover/" + d.ds}
                        className="group flex items-center gap-4 rounded-xl border bg-card pt-6 pb-6 pl-6 pr-6 transition-colors hover:bg-muted/50"
                    >
                        <IconChip icon={File01Icon} tone="blue" />
                        <div className="min-w-0 flex-1">
                            <p className="font-semibold">{d.ds}</p>
                            <p className="text-sm text-muted-foreground">{d.district + " district"}</p>
                            <p className="mt-2 text-sm">
                                {plural(d.confirmed, "confirmed", "confirmed")}
                                {" · "}
                                {plural(d.open_count, "open", "open")}
                            </p>
                        </div>
                        <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
                    </Link>
                }}
            </div>
        }}
    </div>
}
