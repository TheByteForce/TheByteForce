"""Officer: the division map and the best rescue run through waiting households."""

import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Route01Icon }
import type from ekata.geo { MapLayers, RoutePlan }
import from ekata.geo_api { map_layers, division_route }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.native_select { NativeSelectOption }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.page_parts { PageHero, SelectField }
import from ...components.app.map { SituationMap, MapLegend, RouteSummary }

glob STOP_CHOICES: list[str] = ["3", "4", "5", "6", "7", "8"];

def:pub OfficerMapPage -> JsxPage {
    ctx: any = use_desk();
    nav = useNavigate();
    has layers: MapLayers | None = None;
    has route: RoutePlan | None = None;
    has stops: str = "5";
    has planning: bool = False;
    has err: str = "";
    scope: str = ("ds:" + ctx.ds) if ctx.ds != "" else "all";

    async can with (ctx.tick, scope) entry {
        try {
            layers = await map_layers(scope, ctx.tick);
        } except Exception as ex {
            layers = None;
        }
    }

    async def plan -> None {
        if planning or ctx.ds == "" {
            return;
        }
        planning = True;
        err = "";
        try {
            route = await division_route(ctx.ds, int(stops));
        } except Exception as ex {
            err = "Could not plan the route: " + str(ex);
        }
        planning = False;
    }

    waiting_n: int = len(layers.incidents) if layers else 0;
    vulnerable_n: int = len([p for p in layers.incidents if len(p.vulnerable) > 0]) if layers else 0;

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Division officer · " + (ctx.ds if ctx.ds != "" else "Map")}
            title="Plan the rescue run."
            description="See every waiting household in your division and get the best order to reach them, by road where roads are open."
            image="/static/assets/images/aerial-rescue.jpg"
            imageAlt="A rescue helicopter above a flooded river valley"
            capsules={[[f"{waiting_n} households on the map", "blue"], [f"{vulnerable_n} with vulnerable people", "amber"]]}
        >
            {if ctx.ds != "" {
                <SelectField id="stops" value={stops} className="w-28 rounded-full bg-white/90 pl-3 text-foreground" onChange={lambda (e: ChangeEvent) { stops = e.target.value; }}>
                    {for n in STOP_CHOICES {
                        <NativeSelectOption key={n} value={n}>{n + " stops"}</NativeSelectOption>
                    }}
                </SelectField>
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
                    <CardTitle>{(ctx.ds + " division") if ctx.ds != "" else "All divisions"}</CardTitle>
                    <CardDescription>Select a household on the map to open its case.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <SituationMap
                        layers={layers}
                        route={route}
                        height="h-[460px] md:h-[560px]"
                        onSelect={lambda (id: str) { nav("/officer/cases/" + id); }}
                    />
                    <MapLegend withRoute={route is not None} />
                </CardContent>
            </Card>
            <Card>
                <CardHeader>
                    <CardTitle>Planned route</CardTitle>
                    <CardDescription>The route agent weighs vulnerable people, headcount and travel time.</CardDescription>
                </CardHeader>
                <CardContent>
                    {if ctx.ds == "" {
                        <p className="text-sm text-muted-foreground">Choose your division in the sidebar to plan a run.</p>
                    } elif route is None {
                        <p className="text-sm text-muted-foreground">Pick how many stops, then plan the best route.</p>
                    } else {
                        <RouteSummary route={route} />
                    }}
                </CardContent>
            </Card>
        </div>
    </div>
}
