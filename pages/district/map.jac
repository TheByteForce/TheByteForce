"""District: the whole situation map and a rescue run for any division."""

import from "@jac/runtime" { useNavigate }
import type from ekata.geo { MapLayers, RoutePlan }
import from ekata.geo_api { map_layers, division_route }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.native_select { NativeSelectOption }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.page_parts { PageHero, SelectField }
import from ...components.app.portals { run_divisions }
import from ...components.app.map { SituationMap, MapLegend, RouteSummary }

def:pub DistrictMapPage -> JsxPage {
    ctx: any = use_desk();
    nav = useNavigate();
    has layers: MapLayers | None = None;
    has route: RoutePlan | None = None;
    has run_for: str = "";
    has planning: bool = False;
    has err: str = "";

    async can with [ctx.tick] entry {
        try {
            layers = await map_layers("all", ctx.tick);
        } except Exception as ex {
            layers = layers;
        }
    }

    async def plan(ds: str) -> None {
        run_for = ds;
        if ds == "" {
            route = None;
            return;
        }
        planning = True;
        err = "";
        try {
            route = await division_route(ds, 5);
        } except Exception as ex {
            err = "Could not plan the route: " + str(ex);
        }
        planning = False;
    }

    waiting_n: int = len(layers.incidents) if layers else 0;
    zones_n: int = len(layers.zones) if layers else 0;
    shelters_n: int = len(layers.shelters) if layers else 0;

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District coordination · Situation map"
            title="The whole flood, on one map."
            description="Every waiting household, warning areas from official bulletins, shelters and relief group bases across Kegalle and Ratnapura."
            image="/static/assets/images/satellite.jpg"
            imageAlt="Satellite view of flooding across Sri Lanka"
            capsules={[[f"{waiting_n} households", "blue"], [f"{zones_n} warning areas", "orange"], [f"{shelters_n} shelters", "green"]]}
        >
            <SelectField id="run-for" value={run_for} className="w-56 rounded-full bg-white/90 pl-3 text-foreground" onChange={lambda (e: ChangeEvent) { plan(e.target.value); }}>
                <NativeSelectOption value="">Plan a rescue run for...</NativeSelectOption>
                {for d in run_divisions() {
                    <NativeSelectOption key={d} value={d}>{d}</NativeSelectOption>
                }}
            </SelectField>
        </PageHero>
        {if err != "" {
            <Alert variant="destructive">
                <AlertDescription>{err}</AlertDescription>
            </Alert>
        }}
        <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
            <Card className="xl:col-span-2">
                <CardHeader>
                    <CardTitle>Kegalle and Ratnapura</CardTitle>
                    <CardDescription>Select a household to open its case.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <SituationMap layers={layers} route={route} height="h-[480px] md:h-[600px]" onSelect={lambda (id: str) { nav("/officer/cases/" + id); }} />
                    <MapLegend withRoute={route is not None} />
                </CardContent>
            </Card>
            <Card>
                <CardHeader>
                    <CardTitle>{("Rescue run: " + run_for) if run_for != "" else "Rescue run"}</CardTitle>
                    <CardDescription>Choose a division above to plan its best run.</CardDescription>
                </CardHeader>
                <CardContent>
                    {if planning {
                        <p className="text-sm text-muted-foreground">Planning the route...</p>
                    } elif route is None {
                        <p className="text-sm text-muted-foreground">No run planned yet.</p>
                    } else {
                        <RouteSummary route={route} />
                    }}
                </CardContent>
            </Card>
        </div>
    </div>
}
