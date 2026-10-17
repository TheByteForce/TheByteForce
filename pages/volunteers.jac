"""Volunteer offers: which open incidents each offer of help could serve."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    UserGroupIcon, BoatIcon, TruckIcon, Restaurant01Icon, DropletIcon, Home01Icon, HealthIcon
}
import type from ekata.volunteer_centre { OfferMatch }
import from ekata.coordination_api { volunteer_offers }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.app.desk_state { use_desk }
import from ..components.app.tags { Tag }
import from ..components.app.labels { plural, place_label, pretty }
import from ..components.app.page_parts { PageHeader, EmptyNote, LoadingRows }

def:pub resource_icon(resource: str) -> any {
    if resource == "boat" {
        return BoatIcon;
    }
    if resource == "vehicle" {
        return TruckIcon;
    }
    if resource == "food" {
        return Restaurant01Icon;
    }
    if resource == "water" {
        return DropletIcon;
    }
    if resource == "shelter" {
        return Home01Icon;
    }
    if resource == "medical" {
        return HealthIcon;
    }
    return UserGroupIcon;
}

def:pub VolunteersPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[OfferMatch] = [];
    has loaded: bool = False;

    async def load(t: int) -> None {
        try {
            rows = await volunteer_offers(t);
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
            title="Volunteer offers"
            description="Offers of boats, vehicles, food, water, shelter and medical help, listed against the open incidents they could serve. This page only lists matches; a person decides who to dispatch."
            image="/static/assets/images/relief-supplies.jpg"
            imageAlt="Bottled water and medical supplies stacked for flood relief"
        />
        <p className="text-sm text-muted-foreground">{plural(len(rows), "match", "matches")}</p>
        {if not loaded {
            <LoadingRows count={3} className="h-24" />
        } elif len(rows) == 0 {
            <EmptyNote
                title="No matches yet"
                description="When someone offers help that fits an open need, the match appears here."
                icon={UserGroupIcon}
            />
        } else {
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                {for o in rows {
                    <Card key={o.offer_msg_id + ">" + o.inc_id}>
                        <CardHeader>
                            <div className="flex items-center gap-2">
                                <span className="flex size-8 items-center justify-center rounded-lg bg-muted">
                                    <HugeiconsIcon icon={resource_icon(o.resource)} strokeWidth={2} className="size-4" />
                                </span>
                                <CardTitle>{pretty(o.resource)}</CardTitle>
                            </div>
                            <CardDescription>{"Offer " + o.offer_msg_id}</CardDescription>
                        </CardHeader>
                        <CardContent className="flex flex-col gap-4">
                            <p className="text-sm leading-relaxed">{o.offer_text}</p>
                            <div className="flex flex-wrap items-center gap-2 text-sm">
                                <span className="text-muted-foreground">Could serve</span>
                                <Link to={"/incidents/" + o.inc_id} className="font-mono font-medium text-primary underline-offset-4 hover:underline">
                                    {o.inc_id}
                                </Link>
                                <span className="text-muted-foreground">{"at " + place_label(o.inc_place)}</span>
                                <Tag label={"Same area" if o.same_area else "Different area"} tone={"green" if o.same_area else "slate"} />
                            </div>
                            <p className="text-sm text-muted-foreground">{o.reason}</p>
                        </CardContent>
                    </Card>
                }}
            </div>
        }}
    </div>
}
