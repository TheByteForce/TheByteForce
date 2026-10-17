"""Map and route page for the relief group portal."""

import from "react" { useEffect }
import from ekata.geo_api { map_layers, group_route }
import type from ekata.geo { MapLayers, RoutePlan }
import from .map { EkataMap, MapLegend, RouteSummary }

def:pub NgoMapPage(office: str) -> JsxElement {
    has layers: MapLayers | None = None;
    has route: RoutePlan | None = None;
    has busy: bool = False;
    has error: str = "";

    async def load -> None {
        try {
            layers = await map_layers("ngo:" + office, int(Date.now()));
            error = "";
        } except Exception as e {
            error = "Could not load the map. It will retry.";
        }
    }
    async def plan -> None {
        busy = True;
        try {
            route = await group_route(office, 6);
            error = "";
        } except Exception as e {
            error = "Could not plan a route just now. Please try again.";
        }
        busy = False;
    }
    async can with [office] entry {
        route = None;
        await load();
    }
    useEffect(
        lambda {
            timer = setInterval(lambda { load(); }, 8000);
            return lambda { clearInterval(timer); };
        },
        [office]
    );

    empty_route = route is not None and len(route.stops) == 0;
    <section className="space-y-4">
        {if error != "" {
            <p role="alert" className="text-[13px] text-blocked">{error}</p>
        }}
        <div className="flex flex-wrap items-center gap-3">
            <button
                type="button"
                disabled={busy}
                className="min-h-10 rounded-lg bg-[#43204F] px-4 text-[15px] font-semibold text-white hover:bg-[#351940] disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                onClick={lambda (e: MouseEvent) { plan(); }}
            >
                Plan the best route
            </button>
            {if busy {
                <span className="text-[13px] text-muted-foreground">Planning the route...</span>
            }}
        </div>
        <div className="grid gap-4 lg:grid-cols-3">
            <div className="space-y-3 lg:col-span-2">
                <EkataMap layers={layers} route={route} height="h-[560px]"/>
                <MapLegend withRoute={route is not None and not empty_route}/>
            </div>
            <div>
                {if route is not None and not empty_route {
                    <RouteSummary route={route}/>
                }}
                {if route is not None and empty_route {
                    <div className="rounded-xl border border-border bg-card p-5">
                        <p className="text-[15px]">{route.reason}</p>
                    </div>
                }}
                {if route is None {
                    <div className="rounded-xl border border-border bg-card p-5">
                        <p className="text-[15px] text-muted-foreground">
                            Ekata plans from your base over your open requests, and says why it chose that order.
                        </p>
                    </div>
                }}
            </div>
        </div>
    </section>
}
