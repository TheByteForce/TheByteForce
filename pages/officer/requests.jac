"""Officer: relief requests raised for households in your division."""

import from "@jac/runtime" { Link }
import from "@hugeicons/core-free-icons" { TruckIcon }
import type from ekata.portal { RequestView }
import type from ekata.views { QueueRow }
import from ekata.portal_api { all_requests, officer_queue }
import from ...components.ui.card { Card, CardContent }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { RequestTag, VulnerableTag }
import from ...components.app.labels { plural, pretty, people_label, place_label }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows }

def:pub count_status(rows: list[RequestView], status: str) -> int {
    return len([r for r in rows if r.status == status]);
}

def:pub OfficerRequestsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[RequestView] = [];
    has loaded: bool = False;

    async can with (ctx.tick, ctx.ds) entry {
        try {
            if ctx.ds == "" {
                rows = await all_requests(ctx.tick);
            } else {
                queue = await officer_queue(ctx.ds, ctx.tick);
                ids: list[str] = [q.inc_id for q in queue];
                every = await all_requests(ctx.tick);
                rows = [r for r in every if r.inc_id in ids];
            }
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Division officer · " + (ctx.ds if ctx.ds != "" else "All divisions")}
            title="Help you have asked for."
            description="Boats, medicine, food, water, shelter and transport requested for households, and which relief group is bringing them."
            image="/static/assets/images/volunteers-desk.jpg"
            imageAlt="Volunteers helping residents at a disaster recovery centre"
            capsules={[
                [plural(len(rows), "request", "requests"), "blue"],
                [f"{count_status(rows, 'REQUESTED')} waiting for a group", "amber"],
                [f"{count_status(rows, 'DISPATCHED')} on the way", "violet"],
                [f"{count_status(rows, 'UNCOVERED')} no group can cover", "red"]
            ]}
        />
        {if not loaded {
            <LoadingRows count={4} className="h-20" />
        } elif len(rows) == 0 {
            <EmptyNote
                title="No relief requests yet"
                description="Open a case and use Ask a relief group to request a boat, medicine, food, water, shelter or transport."
                icon={TruckIcon}
            />
        } else {
            <div className="flex flex-col gap-2">
                {for r in rows {
                    <Card key={r.req_id}>
                        <CardContent className="flex flex-col gap-2 sm:flex-row sm:items-start sm:gap-6">
                            <div className="flex min-w-48 flex-col gap-2">
                                <span className="text-lg font-semibold">{pretty(r.need)}</span>
                                <RequestTag status={r.status} />
                            </div>
                            <div className="flex min-w-0 flex-1 flex-col gap-1 text-sm">
                                <Link to={"/officer/cases/" + r.inc_id} className="font-medium text-primary underline-offset-4 hover:underline">
                                    {people_label(r.headcount) + " at " + place_label(r.place)}
                                </Link>
                                <div className="flex flex-wrap gap-1">
                                    {for v in r.vulnerable {
                                        <VulnerableTag key={v} flag={v} />
                                    }}
                                </div>
                                {if r.ngo != "" {
                                    <p>{r.ngo + (" · " + r.ngo_contact if r.ngo_contact != "" else "")}</p>
                                }}
                                {if r.reason != "" {
                                    <p className="text-muted-foreground">{r.reason}</p>
                                }}
                            </div>
                            <span className="font-mono text-xs text-muted-foreground">{r.req_id + " · " + r.storm_time}</span>
                        </CardContent>
                    </Card>
                }}
            </div>
        }}
    </div>
}
