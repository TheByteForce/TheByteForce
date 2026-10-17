"""The Ekata map, shared by every portal (Leaflet + OpenStreetMap, no key).

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
import type from ekata.geo { MapLayers, RoutePlan }

def:pub tone_hex(tone: str) -> str {
    if tone == "alert" {
        return "#E8590C";
    }
    if tone == "ok" {
        return "#2F7D4F";
    }
    if tone == "blocked" {
        return "#B42318";
    }
    return "#1F5F7A";
}

def:pub stop_icon(label: str, base: bool) -> any {
    return divIcon({
        "className": "",
        "html": "<div class='ekata-stop" + (" is-base" if base else "") + "'>" + label + "</div>",
        "iconSize": [30, 30],
        "iconAnchor": [15, 15]
    });
}

# Moves the view when the centre or zoom changes (MapContainer only reads them once).
def:pub Recenter(lat: float, lon: float, zoom: int) -> JsxElement {
    m = useMap();
    useEffect(
        lambda { m.setView([lat, lon], zoom); return None; },
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
            return None;
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
        <Polyline
            positions={route.path}
            pathOptions={{"color": "#14212B", "weight": 4, "opacity": 0.8}}
        />
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
        <FitRoute path={route.path}/>
    </>
}

def:pub EkataMap(
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

    <div className={"relative overflow-hidden rounded-xl border border-border " + height}>
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
            <Recenter lat={lat} lon={lon} zoom={zoom}/>
            {if pickable and onPick is not None {
                <ClickPicker onPick={onPick}/>
            }}
            {if layers is not None {
                <>
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
                            pathOptions={{"color": "#2F7D4F", "fillColor": "#FFFFFF", "fillOpacity": 1, "weight": 3}}
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
                            pathOptions={{"color": "#43204F", "fillColor": "#43204F", "fillOpacity": 0.9, "weight": 2}}
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
                </>
            }}
            {if route is not None {
                <RouteLayer route={route}/>
            }}
            {if pickedLat != 0.0 {
                <Marker position={[pickedLat, pickedLon]} icon={stop_icon("!", False)}>
                    <Tooltip permanent={True}>Your location</Tooltip>
                </Marker>
            }}
        </MapContainer>
    </div>
}

# A plain legend under the map.
def:pub MapLegend(withRoute: bool = False) -> JsxElement {
    <div className="mt-2 flex flex-wrap gap-x-5 gap-y-1 text-[13px] text-muted-foreground">
        <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-full bg-[#E8590C]"></span>
            Vulnerable people waiting
        </span>
        <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-full bg-[#1F5F7A]"></span>
            Household waiting
        </span>
        <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-full bg-[#2F7D4F]"></span>
            Reached
        </span>
        <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-full border-[3px] border-[#2F7D4F] bg-white"></span>
            Shelter
        </span>
        <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-full bg-[#43204F]"></span>
            Relief group base
        </span>
        <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-full border border-dashed border-[#E8590C]"></span>
            Warning area
        </span>
        {if withRoute {
            <span className="flex items-center gap-1.5">
                <span className="h-1 w-5 rounded bg-[#14212B]"></span>
                Planned route
            </span>
        }}
    </div>
}

# The route agent's plan as a numbered list with its reason and the options it weighed.
def:pub RouteSummary(route: RoutePlan) -> JsxElement {
    <div className="rounded-xl border border-border bg-card p-5">
        {if not route.ok {
            <p className="text-[15px] text-muted-foreground">{route.reason}</p>
        } else {
            <div>
                <p className="text-[13px] text-muted-foreground">
                    {f"From {route.origin_label}: {len(route.stops)} stops, {route.people} people, about {route.duration_min} min, {route.distance_km} km" + ("" if route.road else " (straight-line estimate)")}
                </p>
                <p className="mt-2 text-[15px] leading-relaxed">{route.reason}</p>
                <ol className="mt-4 space-y-2.5">
                    {for s in route.stops {
                        <li key={"l" + s.id} className="flex gap-3">
                            <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-foreground text-[13px] font-bold text-background">
                                {str(s.order)}
                            </span>
                            <span className="min-w-0">
                                <span className="block text-[15px] font-semibold leading-snug">{s.label}</span>
                                <span className="block text-[13px] text-muted-foreground">
                                    {f"About {s.eta_min} min. " + s.why}
                                </span>
                            </span>
                        </li>
                    }}
                </ol>
                {if len(route.skipped) > 0 {
                    <p className="mt-4 text-[13px] text-muted-foreground">
                        {"Left for the next run: " + ", ".join(route.skipped)}
                    </p>
                }}
                <div className="mt-4 grid gap-2 sm:grid-cols-3">
                    {for o in route.options {
                        <div
                            key={o.name}
                            className={"rounded-lg border px-3 py-2 text-[13px] "
                                + ("border-foreground bg-muted" if o.name == route.chosen else "border-border")}
                        >
                            <p className="font-semibold">{o.title + (" (chosen)" if o.name == route.chosen else "")}</p>
                            <p className="text-muted-foreground">
                                {f"{o.vulnerable_households} vulnerable, {o.people} people, {o.duration_min} min"}
                            </p>
                        </div>
                    }}
                </div>
            </div>
        }}
    </div>
}
