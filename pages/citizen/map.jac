"""Citizen: the situation map for your area (households are anonymised)."""

import type from crisisconnect.geo { MapLayers }
import from crisisconnect.geo_api { map_layers }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.app.desk_state { use_desk }
import from ...components.app.page_parts { PageHero }
import from ...components.app.map { SituationMap, MapLegend }

def:pub CitizenMapPage -> JsxPage {
    ctx: any = use_desk();
    has layers: MapLayers | None = None;
    scope: str = ("area:" + ctx.area) if ctx.area != "" else "all";

    async can with (ctx.tick, scope) entry {
        try {
            layers = await map_layers(scope, ctx.tick);
        } except Exception as ex {
            layers = None;
        }
    }

    shelters_n: int = len(layers.shelters) if layers else 0;
    zones_n: int = len(layers.zones) if layers else 0;
    waiting_n: int = len(layers.incidents) if layers else 0;

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Citizen · Situation map"
            title={("Flood situation in " + ctx.area) if ctx.area != "" else "Flood situation near you"}
            description="Shelters, warning areas and households waiting for help. Choose your area in the sidebar to zoom in."
            image="/static/assets/images/satellite.jpg"
            imageAlt="Satellite view of flooding across Sri Lanka"
            capsules={[[f"{shelters_n} shelters", "green"], [f"{zones_n} warning areas", "orange"], [f"{waiting_n} households waiting", "blue"]]}
        />
        <Card>
            <CardHeader>
                <CardTitle>Map</CardTitle>
                <CardDescription>{layers.note if layers and layers.note != "" else "Updated every few seconds."}</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
                <SituationMap layers={layers} height="h-[420px] md:h-[520px]" showBases={False} />
                <MapLegend />
            </CardContent>
        </Card>
    </div>
}
