"""Citizen: send an SOS, optionally with a pin on the map."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Location01Icon, SentIcon, Search01Icon, Home01Icon }
import type from crisisconnect.portal { CitizenStatus }
import type from crisisconnect.geo { MapLayers, NearbyPlace }
import from crisisconnect.portal_api { citizen_send }
import from crisisconnect.geo_api { map_layers, report_at, shelters_near }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.textarea { Textarea }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk, remember_ref, fresh_tick }
import from ...components.app.page_parts { PageHero }
import from ...components.app.map { SituationMap }

def:pub SosPage -> JsxPage {
    ctx: any = use_desk();
    has layers: MapLayers | None = None;
    has text: str = "";
    has lat: float = 0.0;
    has lon: float = 0.0;
    has sending: bool = False;
    has locating: bool = False;
    has geo_note: str = "";
    has err: str = "";
    has receipt: CitizenStatus | None = None;
    has shelters: list[NearbyPlace] = [];

    scope: str = ("area:" + ctx.area) if ctx.area != "" else "all";

    async can with [scope] entry {
        try {
            layers = await map_layers(scope, fresh_tick());
        } except Exception as ex {
            layers = None;
        }
    }

    def pick(a: float, b: float) -> None {
        lat = a;
        lon = b;
        geo_note = "";
    }

    def locate -> None {
        geo: any = navigator.geolocation;
        if not geo {
            geo_note = "This browser cannot share your location. Tap the map instead.";
            return;
        }
        locating = True;
        geo.getCurrentPosition(
            lambda (pos: any) { lat = pos.coords.latitude; lon = pos.coords.longitude; locating = False; geo_note = ""; },
            lambda (e: any) { locating = False; geo_note = "We could not get your location. Tap the map where you are."; }
        );
    }

    async def send -> None {
        msg = text.strip();
        if msg == "" or sending {
            return;
        }
        sending = True;
        err = "";
        try {
            if lat != 0.0 {
                r = await report_at(msg, lat, lon);
                receipt = r;
                shelters = await shelters_near(lat, lon, fresh_tick());
            } else {
                receipt = await citizen_send(msg, "SMS");
                shelters = [];
            }
            if receipt is not None {
                remember_ref(receipt.msg_id);
            }
            text = "";
            ctx.bump();
        } except Exception as ex {
            err = "Your message did not go through. Please try again, or call your local emergency number. (" + str(ex) + ")";
        }
        sending = False;
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Citizen · Send an SOS"
            title="Ask for help. A division officer will call you."
            description="Say where you are, how many people are with you and who cannot move. Write in Sinhala, Tamil or English."
            image="/static/assets/images/helicopter-response.jpg"
            imageAlt="A rescue helicopter flying low during a flood response"
            capsules={[["Sinhala, Tamil or English", "blue"], ["Track it with your reference", "green"], ["In danger now? Call emergency services", "red"]]}
        />

        {if receipt is not None {
            <Card className="border-emerald-200 bg-emerald-50/60">
                <CardHeader>
                    <CardTitle>We received your message</CardTitle>
                    <CardDescription>Keep this reference number. You can use it to see what is happening.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <p className="font-mono text-3xl font-semibold tracking-wider">{receipt.msg_id}</p>
                    <p className="text-sm">{receipt.stage_label + ". " + receipt.detail}</p>
                    <div className="flex flex-wrap gap-2">
                        <Button asChild={True} className="rounded-full pl-4 pr-4">
                            <Link to={"/citizen/track?ref=" + receipt.msg_id}>
                                <HugeiconsIcon icon={Search01Icon} strokeWidth={2} data-icon="inline-start" />
                                Track this request
                            </Link>
                        </Button>
                    </div>
                    {if len(shelters) > 0 {
                        <div className="flex flex-col gap-2">
                            <p className="text-sm font-medium">Nearest shelters</p>
                            <ul className="grid gap-2 sm:grid-cols-3">
                                {for s in shelters {
                                    <li key={s.label} className="rounded-lg border bg-background pt-3 pb-3 pl-3 pr-3 text-sm">
                                        <p className="flex items-center gap-1 font-medium">
                                            <HugeiconsIcon icon={Home01Icon} strokeWidth={2} className="size-4 text-emerald-600" />
                                            {s.label}
                                        </p>
                                        <p className="text-muted-foreground">{f"{s.km:.1f} km · " + s.detail}</p>
                                    </li>
                                }}
                            </ul>
                        </div>
                    }}
                </CardContent>
            </Card>
        }}

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
            <Card className="lg:col-span-3">
                <CardHeader>
                    <CardTitle>Mark where you are</CardTitle>
                    <CardDescription>Tap the map, or share your location. A pin helps the rescue team find you.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <SituationMap
                        layers={layers}
                        height="h-[340px]"
                        pickable={True}
                        onPick={pick}
                        pickedLat={lat}
                        pickedLon={lon}
                        showBases={False}
                    />
                    <div className="flex flex-wrap items-center gap-2">
                        <Button variant="outline" className="rounded-full pl-4 pr-4" disabled={locating} onClick={lambda (e: MouseEvent) { locate(); }}>
                            <HugeiconsIcon icon={Location01Icon} strokeWidth={2} data-icon="inline-start" />
                            {"Finding you..." if locating else "Use my location"}
                        </Button>
                        {if lat != 0.0 {
                            <span className="text-sm text-emerald-700">Pin dropped</span>
                            <button type="button" className="text-sm text-muted-foreground underline underline-offset-4" onClick={lambda (e: MouseEvent) { lat = 0.0; lon = 0.0; }}>
                                Remove pin
                            </button>
                        }}
                    </div>
                    {if geo_note != "" {
                        <p className="text-sm text-muted-foreground">{geo_note}</p>
                    }}
                </CardContent>
            </Card>

            <Card className="lg:col-span-2">
                <CardHeader>
                    <CardTitle>Your message</CardTitle>
                    <CardDescription>Where are you, how many people, and who cannot move?</CardDescription>
                </CardHeader>
                <CardContent>
                    <form className="flex flex-col gap-4" onSubmit={lambda (e: FormEvent) { e.preventDefault(); send(); }}>
                        <label htmlFor="sos-text" className="sr-only">Your message</label>
                        <Textarea
                            id="sos-text"
                            rows={6}
                            value={text}
                            className="text-base"
                            placeholder="Example: Water is inside our house at No 12 Temple Road, Mawanella. 4 of us, my mother cannot walk."
                            onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
                        />
                        <Button type="submit" size="lg" className="rounded-full" disabled={sending or text.strip() == ""}>
                            <HugeiconsIcon icon={SentIcon} strokeWidth={2} data-icon="inline-start" />
                            {"Sending..." if sending else "Send for help"}
                        </Button>
                        {if err != "" {
                            <Alert variant="destructive">
                                <AlertDescription>{err}</AlertDescription>
                            </Alert>
                        }}
                        <p className="text-sm text-muted-foreground">In danger right now? Call your local emergency number first.</p>
                    </form>
                </CardContent>
            </Card>
        </div>
    </div>
}
