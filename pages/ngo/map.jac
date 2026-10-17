"""Relief group: your requests on the map and the best delivery run."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Route01Icon }
import type from crisisconnect.geo { MapLayers, RoutePlan }
import from crisisconnect.geo_api { map_layers, group_route }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.page_parts { PageHero }
import from ...components.app.map { SituationMap, MapLegend, RouteSummary }

def:pub NgoMapPage -> JsxPage {
    ctx: any = use_desk();
    has layers: MapLayers | None = None;
    has route: RoutePlan | None = None;
    has planning: bool = False;
    has err: str = "";
    scope: str = ("ngo:" + ctx.group) if ctx.group != "" else "all";

    async can with (ctx.tick, scope) entry {
        try {
            layers = await map_layers(scope, ctx.tick);
        } except Exception as ex {
            layers = None;
        }
    }

    async def plan -> None {
        if planning or ctx.group == "" {
            return;
        }
        planning = True;
        err = "";
        try {
            route = await group_route(ctx.group, 6);
        } except Exception as ex {
            err = "Could not plan the route: " + str(ex);
        }
        planning = False;
    }

    stops_n: int = len(layers.incidents) if layers else 0;

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Relief group · " + (ctx.group if ctx.group != "" else "Map")}
            title="Plan your delivery run."
            description="Households you have accepted, your base, shelters and warning areas. Plan the best order to reach everyone."
            image="/static/assets/images/aerial-rescue.jpg"
            imageAlt="A rescue helicopter above a flooded river valley"
            capsules={[[f"{stops_n} households linked to your group", "blue"]]}
        >
            {if ctx.group != "" {
                <Button className="rounded-full pl-4 pr-4" disabled={planning} onClick={lambda (e: MouseEvent) { plan(); }}>
                    <HugeiconsIcon icon={Route01Icon} strokeWidth={2} data-icon="inline-start" />
                    {"Planning..." if planning else "Plan the best route"}
                </Button>
            }}
        </PageHero>
        {if err != "" {
            <Alert variant="destructive">
                <AlertDescription>{err}</AlertDescription>
            </Alert>
        }}
        <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
            <Card className="xl:col-span-2">
                <CardHeader>
                    <CardTitle>{ctx.group if ctx.group != "" else "All households"}</CardTitle>
                    <CardDescription>Purple marks relief group bases; green rings are shelters.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <SituationMap layers={layers} route={route} height="h-[460px] md:h-[560px]" />
                    <MapLegend withRoute={route is not None} />
                </CardContent>
            </Card>
            <Card>
                <CardHeader>
                    <CardTitle>Planned run</CardTitle>
                </CardHeader>
                <CardContent>
                    {if ctx.group == "" {
                        <p className="text-sm text-muted-foreground">Choose your group in the sidebar.</p>
                    } elif route is None {
                        <p className="text-sm text-muted-foreground">Plan the best route to see the order of stops.</p>
                    } else {
                        <RouteSummary route={route} />
                    }}
                </CardContent>
            </Card>
        </div>
    </div>
}
