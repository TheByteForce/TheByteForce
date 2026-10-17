"""The situation map shared by every portal (Leaflet + OpenStreetMap, no key).

Layers: households (orange when vulnerable people wait, blue otherwise, green
when reached), warning zones from bulletins, shelters, relief group bases, a
planned route with numbered stops, and an optional dropped pin for citizens.
"""

import from "react" { useEffect }
import from "react-leaflet" {
    MapContainer, TileLayer, CircleMarker, Circle, Polyline, Marker, Popup, Tooltip,
    useMap, useMapEvents
}
import from "leaflet" { divIcon }
import type from crisisconnect.geo { MapLayers, RoutePlan }
import from ..ui.skeleton { Skeleton }
import from ...lib.utils { cn }

def:pub tone_hex(tone: str) -> str {
    if tone == "alert" {
        return "#EA580C";
    }
    if tone == "ok" {
        return "#059669";
    }
    if tone == "blocked" {
        return "#DC2626";
    }
    return "#1D4ED8";
}

def:pub stop_icon(label: str, base: bool) -> any {
    tone: str = "bg-blue-700" if base else "bg-zinc-900";
    return divIcon({
        "className": "",
        "html": "<div class='flex size-7 items-center justify-center rounded-full border-2 border-white text-xs font-bold text-white shadow-md " + tone + "'>" + label + "</div>",
        "iconSize": [28, 28],
        "iconAnchor": [14, 14]
    });
}

# Moves the view when the centre or zoom changes (MapContainer only reads them once).
def:pub Recenter(lat: float, lon: float, zoom: int) -> JsxElement {
    m = useMap();
    useEffect(
        lambda { m.setView([lat, lon], zoom); return lambda { done = True; }; },
        [lat, lon, zoom]
    );
    <></>
}

# Fits the view to a route when one is drawn.
def:pub FitRoute(path: list[list[float]]) -> JsxElement {
    m = useMap();
    useEffect(
        lambda {
            if len(path) > 1 {
                m.fitBounds(path, {"padding": [40, 40]});
            }
            return lambda { done = True; };
        },
        [len(path)]
    );
    <></>
}

def:pub ClickPicker(onPick: Callable[[float, float], None]) -> JsxElement {
    useMapEvents({"click": lambda (e: any) { onPick(e.latlng.lat, e.latlng.lng); }});
    <></>
}

def:pub RouteLayer(route: RoutePlan) -> JsxElement {
    if not route.ok or len(route.stops) == 0 {
        return <></>;
    }
    <>
        <Polyline positions={route.path} pathOptions={{"color": "#18181B", "weight": 4, "opacity": 0.8}} />
        <Marker position={route.origin} icon={stop_icon("B", True)}>
            <Tooltip>{"Start: " + route.origin_label}</Tooltip>
        </Marker>
        {for s in route.stops {
            <Marker key={"r" + s.id} position={[s.lat, s.lon]} icon={stop_icon(str(s.order), False)}>
                <Tooltip>{f"{s.order}. {s.label}, about {s.eta_min} min"}</Tooltip>
                <Popup>
                    <strong>{f"Stop {s.order}: {s.label}"}</strong>
                    <p>{s.why}</p>
                    <p>{f"About {s.eta_min} min from the start"}</p>
                </Popup>
            </Marker>
        }}
        <FitRoute path={route.path} />
    </>
}

def:pub SituationMap(
    layers: MapLayers | None = None,
    route: RoutePlan | None = None,
    height: str = "h-[460px]",
    pickable: bool = False,
    onPick: Callable[[float, float], None] | None = None,
    pickedLat: float = 0.0,
    pickedLon: float = 0.0,
    showBases: bool = True,
    showShelters: bool = True,
    onSelect: Callable[[str], None] | None = None
) -> JsxElement {
    lat: float = 7.02;
    lon: float = 80.40;
    zoom: int = 9;
    if layers is not None {
        lat = layers.center[0];
        lon = layers.center[1];
        zoom = layers.zoom;
    }

    if layers is None {
        return
            <div className={cn("relative overflow-hidden rounded-xl border", height)}>
                <Skeleton className="h-full w-full rounded-none" />
                <p className="absolute inset-0 flex items-center justify-center text-sm text-muted-foreground">
                    Loading the map
                </p>
            </div>;
    }
    <div className={cn("relative overflow-hidden rounded-xl border", height)}>
        <MapContainer
            center={[lat, lon]}
            zoom={zoom}
            scrollWheelZoom={True}
            style={{"height": "100%", "width": "100%"}}
        >
            <TileLayer
                attribution="&copy; OpenStreetMap contributors"
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <Recenter lat={lat} lon={lon} zoom={zoom} />
            {if pickable and onPick is not None {
                <ClickPicker onPick={onPick} />
            }}
            {for z in layers.zones {
                <Circle
                    key={"z" + z.label + z.text[:12]}
                    center={[z.lat, z.lon]}
                    radius={z.radius_m}
                    pathOptions={{"color": tone_hex(z.tone), "weight": 1, "fillOpacity": 0.08, "dashArray": "4 6"}}
                >
                    <Tooltip>{z.label}</Tooltip>
                    <Popup>
                        <strong>{z.label}</strong>
                        <p>{z.text}</p>
                    </Popup>
                </Circle>
            }}
            {for s in (layers.shelters if showShelters else []) {
                <CircleMarker
                    key={s.id}
                    center={[s.lat, s.lon]}
                    radius={6}
                    pathOptions={{"color": "#059669", "fillColor": "#FFFFFF", "fillOpacity": 1, "weight": 3}}
                >
                    <Tooltip>{s.label}</Tooltip>
                    <Popup>
                        <strong>{s.label}</strong>
                        <p>{s.detail}</p>
                    </Popup>
                </CircleMarker>
            }}
            {for b in (layers.bases if showBases else []) {
                <CircleMarker
                    key={b.id}
                    center={[b.lat, b.lon]}
                    radius={6}
                    pathOptions={{"color": "#7C3AED", "fillColor": "#7C3AED", "fillOpacity": 0.9, "weight": 2}}
                >
                    <Tooltip>{b.label}</Tooltip>
                    <Popup>
                        <strong>{b.label}</strong>
                        <p>{b.detail}</p>
                    </Popup>
                </CircleMarker>
            }}
            {for p in layers.incidents {
                <CircleMarker
                    key={p.id}
                    center={[p.lat, p.lon]}
                    radius={9 if len(p.vulnerable) > 0 else 7}
                    pathOptions={{"color": "#FFFFFF", "weight": 2, "fillColor": tone_hex(p.tone), "fillOpacity": 0.95}}
                    eventHandlers={{"click": lambda (e: any) { if onSelect is not None { onSelect(p.id); } }}}
                >
                    <Tooltip>{p.label}</Tooltip>
                    <Popup>
                        <strong>{p.label}</strong>
                        <p>{p.detail}</p>
                        {if len(p.vulnerable) > 0 {
                            <p>{"Vulnerable: " + ", ".join(p.vulnerable)}</p>
                        }}
                    </Popup>
                </CircleMarker>
            }}
            {if route is not None {
                <RouteLayer route={route} />
            }}
            {if pickedLat != 0.0 {
                <Marker position={[pickedLat, pickedLon]} icon={stop_icon("!", False)}>
                    <Tooltip permanent={True}>Your location</Tooltip>
                </Marker>
            }}
        </MapContainer>
    </div>
}

def:pub LegendDot(label: str, className: str) -> JsxElement {
    <span className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className={cn("size-3 rounded-full", className)}></span>
        {label}
    </span>
}

def:pub MapLegend(withRoute: bool = False) -> JsxElement {
    <div className="flex flex-wrap gap-x-4 gap-y-2 text-sm text-muted-foreground">
        <LegendDot label="Vulnerable people waiting" className="bg-orange-600" />
        <LegendDot label="Household waiting" className="bg-blue-700" />
        <LegendDot label="Reached" className="bg-emerald-600" />
        <LegendDot label="Shelter" className="border-[3px] border-emerald-600 bg-white" />
        <LegendDot label="Relief group base" className="bg-violet-600" />
        <LegendDot label="Warning area" className="border border-dashed border-orange-600" />
        {if withRoute {
            <span className="inline-flex items-center gap-1.5">
                <span aria-hidden="true" className="h-1 w-5 rounded bg-zinc-900"></span>
                Planned route (not checked for flooding)
            </span>
        }}
    </div>
}

# The route agent's plan: numbered stops, its reason, and the options it weighed.
def:pub RouteSummary(route: RoutePlan) -> JsxElement {
    if not route.ok {
        return <p className="text-sm text-muted-foreground">{route.reason}</p>;
    }
    <div className="flex flex-col gap-4">
        <p className="text-sm text-muted-foreground">
            {f"From {route.origin_label}: {len(route.stops)} stops, {route.people} people, about {route.duration_min} min, {route.distance_km} km" + ("" if route.road else " (straight-line estimate)")}
        </p>
        <p className="text-sm leading-relaxed">{route.reason}</p>
        <p className="text-xs text-muted-foreground">Road route, not checked for flooding. Division-derived locations are approximate.</p>
        <ol className="flex flex-col gap-3">
            {for s in route.stops {
                <li key={"l" + s.id} className="flex gap-3">
                    <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-zinc-900 text-xs font-bold text-white">
                        {str(s.order)}
                    </span>
                    <span className="min-w-0">
                        <span className="block text-sm font-medium leading-snug">{s.label}</span>
                        <span className="block text-xs text-muted-foreground">{f"About {s.eta_min} min. " + s.why}</span>
                    </span>
                </li>
            }}
        </ol>
        {if len(route.skipped) > 0 {
            <p className="text-xs text-muted-foreground">{"Left for the next run: " + ", ".join(route.skipped)}</p>
        }}
        <div className="grid gap-2 sm:grid-cols-3">
            {for o in route.options {
                <div
                    key={o.name}
                    className={cn("rounded-lg border pt-2 pb-2 pl-3 pr-3 text-xs", "border-primary bg-blue-50" if o.name == route.chosen else "")}
                >
                    <p className="font-medium">{o.title + (" (chosen)" if o.name == route.chosen else "")}</p>
                    <p className="text-muted-foreground">{f"{o.vulnerable_households} vulnerable, {o.people} people, {o.duration_min} min"}</p>
                </div>
            }}
        </div>
    </div>
}
