"""A relief request as a group sees it, with the next action it can take.
Co-located component (returns JsxElement), not a route."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkCircle01Icon, Cancel01Icon, DeliveryTruck01Icon, PackageDeliveredIcon }
import type from ekata.portal { RequestView }
import from ekata.portal_api { respond_request }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.app.tags { RequestTag, VulnerableTag }
import from ...components.app.labels { pretty, people_label, place_label }
import from ...lib.utils { cn }

def:pub RequestCard(r: RequestView, group: str, onDone: Callable[[str], None]) -> JsxElement {
    has busy: bool = False;
    has err: str = "";
    declined: bool = group in r.declined_by and r.ngo != group;

    async def respond(action: str, label: str) -> None {
        if busy {
            return;
        }
        busy = True;
        err = "";
        try {
            res = await respond_request(r.req_id, group, action);
            if res is None {
                err = "This request has moved to another group.";
            } else {
                onDone(label);
            }
        } except Exception as ex {
            err = str(ex);
        }
        busy = False;
    }

    <Card className={cn("", "opacity-70" if declined else "")}>
        <CardHeader>
            <div className="flex flex-wrap items-center gap-2">
                <CardTitle className="text-lg">{pretty(r.need)}</CardTitle>
                <RequestTag status={r.status} />
                {for v in r.vulnerable {
                    <VulnerableTag key={v} flag={v} />
                }}
                <span className="ml-auto font-mono text-xs text-muted-foreground">{r.req_id}</span>
            </div>
            <CardDescription>{people_label(r.headcount) + " at " + place_label(r.place)}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
            <div className="flex flex-col gap-1 text-sm">
                <p className="text-muted-foreground">{"Requested by " + r.requested_by + " at " + r.storm_time}</p>
                {if r.reason != "" {
                    <p><span className="font-medium">Why this came to you: </span>{r.reason}</p>
                }}
                {if declined {
                    <p className="text-muted-foreground">{"You declined this request. It is now with " + (r.ngo if r.ngo != "" else "the district desk") + "."}</p>
                }}
            </div>
            {if not declined {
                <div className="flex flex-wrap gap-2">
                    {if r.status == "REQUESTED" {
                        <Button className="rounded-full pl-4 pr-4" disabled={busy} onClick={lambda (e: MouseEvent) { respond("accept", "You accepted " + r.req_id + "."); }}>
                            <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} data-icon="inline-start" />
                            Accept
                        </Button>
                        <Button variant="outline" className="rounded-full pl-4 pr-4" disabled={busy} onClick={lambda (e: MouseEvent) { respond("decline", "Passed " + r.req_id + " to another group."); }}>
                            <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} data-icon="inline-start" />
                            We can't help
                        </Button>
                    } elif r.status == "ACCEPTED" {
                        <Button className="rounded-full pl-4 pr-4" disabled={busy} onClick={lambda (e: MouseEvent) { respond("dispatched", r.req_id + " is on the way."); }}>
                            <HugeiconsIcon icon={DeliveryTruck01Icon} strokeWidth={2} data-icon="inline-start" />
                            Mark on the way
                        </Button>
                    } elif r.status == "DISPATCHED" {
                        <Button className="rounded-full pl-4 pr-4" disabled={busy} onClick={lambda (e: MouseEvent) { respond("delivered", r.req_id + " delivered. Thank you."); }}>
                            <HugeiconsIcon icon={PackageDeliveredIcon} strokeWidth={2} data-icon="inline-start" />
                            Mark delivered
                        </Button>
                    }}
                </div>
            }}
            {if err != "" {
                <p role="alert" className="text-sm text-destructive">{err}</p>
            }}
        </CardContent>
    </Card>
}
