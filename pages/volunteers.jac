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
import from ..components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }

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

    same_n: int = len([o for o in rows if o.same_area]);
    offer_ids: list[str] = [];
    for o in rows {
        if o.offer_msg_id not in offer_ids {
            offer_ids = offer_ids + [o.offer_msg_id];
        }
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Coordination · Volunteer offers"
            title="Offers of help, matched to needs."
            description="Boats, vehicles, food, water, shelter and medical help, listed against the open incidents they could serve. This page only lists matches; a person decides who to dispatch."
            image="/static/assets/images/volunteers-desk.jpg"
            imageAlt="Volunteers helping residents at a disaster recovery centre"
            capsules={[
                [plural(len(offer_ids), "offer", "offers"), "green"],
                [plural(len(rows), "match", "matches"), "blue"],
                [f"{same_n} in the same area", "violet"]
            ]}
        />
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
                                <IconChip icon={resource_icon(o.resource)} tone="green" />
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
