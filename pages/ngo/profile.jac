"""Relief group: your registry entry."""

import from "@hugeicons/core-free-icons" { Building03Icon }
import type from crisisconnect.portal { NgoView }
import from crisisconnect.portal_api { ngos }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { Tag }
import from ...components.app.labels { pretty }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }

def:pub NgoProfilePage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[NgoView] = [];
    has loaded: bool = False;

    async can with (ctx.tick, ctx.group) entry {
        try {
            rows = await ngos(ctx.tick);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    mine: list[NgoView] = [g for g in rows if g.office == ctx.group];

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Relief group · Your group"
            title={ctx.group if ctx.group != "" else "Your group"}
            description="How CrisisConnect knows your group: where you work, what you can supply, and how officers reach you."
            image="/static/assets/images/volunteers-desk.jpg"
            imageAlt="Volunteers helping residents at a disaster recovery centre"
        />
        {if not loaded {
            <LoadingRows count={2} className="h-32" />
        } elif len(mine) == 0 {
            <EmptyNote title="No group chosen yet" description="Choose your group in the sidebar." icon={Building03Icon} />
        } else {
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-4">
                        <IconChip icon={Building03Icon} tone="violet" />
                        <div className="flex flex-col gap-1">
                            <CardTitle>{mine[0].office}</CardTitle>
                            <CardDescription>{mine[0].contact}</CardDescription>
                        </div>
                    </div>
                </CardHeader>
                <CardContent className="grid gap-6 sm:grid-cols-3">
                    <div className="flex flex-col gap-2">
                        <p className="text-sm font-medium">Areas served</p>
                        <div className="flex flex-wrap gap-2">
                            {for a in mine[0].areas {
                                <Tag key={a} label={a} tone="blue" />
                            }}
                        </div>
                    </div>
                    <div className="flex flex-col gap-2">
                        <p className="text-sm font-medium">What you offer</p>
                        <div className="flex flex-wrap gap-2">
                            {for o in mine[0].offers {
                                <Tag key={o} label={pretty(o)} tone="green" />
                            }}
                        </div>
                    </div>
                    <div className="flex flex-col gap-2">
                        <p className="text-sm font-medium">Open requests</p>
                        <p className="text-3xl font-semibold tabular-nums">{str(mine[0].open_requests)}</p>
                    </div>
                </CardContent>
            </Card>
        }}
    </div>
}
