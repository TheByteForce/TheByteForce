"""DS hand-over: pick a Divisional Secretariat division to open its sheet."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { File01Icon, ArrowRight01Icon }
import type from ekata.ds_sheet { DsCount }
import from ekata.coordination_api { ds_divisions }
import from ...components.app.desk_state { use_desk }
import from ...components.app.labels { plural }
import from ...components.app.page_parts { PageHeader, EmptyNote, LoadingRows }

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

    <div className="flex flex-col gap-6">
        <PageHeader
            title="DS hand-over"
            description="A clean sheet of phone-verified incidents for each Divisional Secretariat division, ready to hand to DS and GN officers."
            image="/static/assets/images/satellite.jpg"
            imageAlt="Satellite view of flooding across Sri Lanka"
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
                        to={"/handover/" + d.ds}
                        className="group flex items-center gap-4 rounded-xl border bg-card pt-6 pb-6 pl-6 pr-6 transition-colors hover:bg-muted/50"
                    >
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
