"""Citizen: official bulletins for your area."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Megaphone01Icon }
import type from ekata.portal { BulletinView }
import from ekata.portal_api { bulletins }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.app.desk_state { use_desk }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }
import from ...components.app.labels { plural }

def:pub BulletinsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[BulletinView] = [];
    has loaded: bool = False;

    async can with (ctx.tick, ctx.area) entry {
        try {
            rows = await bulletins(ctx.area, ctx.tick);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Citizen · Official bulletins"
            title="What the authorities are saying."
            description="Warnings and notices from the Disaster Management Centre, NBRO, the Irrigation Department and the District Secretariat."
            image="/static/assets/images/officials-meeting.jpg"
            imageAlt="Officials around a table at an emergency operations centre"
            capsules={[[plural(len(rows), "bulletin", "bulletins"), "blue"], [ctx.area if ctx.area != "" else "All areas", "green"]]}
        />
        {if not loaded {
            <LoadingRows count={3} className="h-24" />
        } elif len(rows) == 0 {
            <EmptyNote
                title="No bulletins for this area yet"
                description="New bulletins appear here as soon as they are published."
                icon={Megaphone01Icon}
            />
        } else {
            <div className="flex flex-col gap-4">
                {for (i, b) in enumerate(rows) {
                    <Card key={str(i) + b.issued_at}>
                        <CardHeader>
                            <div className="flex items-center gap-4">
                                <IconChip icon={Megaphone01Icon} tone="orange" />
                                <div className="flex flex-col gap-1">
                                    <CardTitle>{b.issuer}</CardTitle>
                                    <CardDescription>{b.area + " · " + b.issued_at}</CardDescription>
                                </div>
                            </div>
                        </CardHeader>
                        <CardContent>
                            <p className="leading-relaxed">{b.text}</p>
                        </CardContent>
                    </Card>
                }}
            </div>
        }}
    </div>
}
