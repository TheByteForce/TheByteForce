"""Relief group: requests you accepted, are delivering, delivered or passed on."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkCircle01Icon, PackageDeliveredIcon }
import type from ekata.portal { RequestView }
import from ekata.portal_api { ngo_requests }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.labels { plural }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows }
import from .request_card { RequestCard }

def:pub NgoDonePage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[RequestView] = [];
    has loaded: bool = False;
    has notice: str = "";

    async can with (ctx.tick, ctx.group) entry {
        if ctx.group == "" {
            loaded = True;
            return;
        }
        try {
            rows = await ngo_requests(ctx.group, ctx.tick);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    shown: list[RequestView] = [r for r in rows if r.status != "REQUESTED" or r.ngo != ctx.group];
    moving_n: int = len([r for r in shown if r.status == "ACCEPTED" or r.status == "DISPATCHED"]);
    delivered_n: int = len([r for r in shown if r.status == "DELIVERED"]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Relief group · " + (ctx.group if ctx.group != "" else "Accepted and delivered")}
            title="What you have taken on."
            description="Mark each request on the way when it leaves, and delivered when it reaches the household. The officer and the family see the change."
            image="/static/assets/images/boat-crossing.jpg"
            imageAlt="Rescue workers crossing flood water by boat"
            capsules={[[f"{moving_n} in progress", "blue"], [f"{delivered_n} delivered", "green"], [plural(len(shown), "request", "requests"), "violet"]]}
        />
        {if notice != "" {
            <Alert>
                <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} />
                <AlertDescription>{notice}</AlertDescription>
            </Alert>
        }}
        {if ctx.group == "" {
            <EmptyNote title="No group chosen yet" description="Choose your group in the sidebar." icon={PackageDeliveredIcon} />
        } elif not loaded {
            <LoadingRows count={3} className="h-40" />
        } elif len(shown) == 0 {
            <EmptyNote
                title="Nothing accepted yet"
                description="Requests you accept show up here so you can mark them on the way and delivered."
                icon={PackageDeliveredIcon}
            />
        } else {
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {for r in shown {
                    <RequestCard key={r.req_id} r={r} group={ctx.group} onDone={lambda (msg: str) { notice = msg; ctx.bump(); }} />
                }}
            </div>
        }}
    </div>
}
