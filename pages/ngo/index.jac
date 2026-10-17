"""Relief group: requests waiting for your answer."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { InboxIcon, CheckmarkCircle01Icon, Building03Icon, ArrowRight01Icon }
import type from crisisconnect.portal { RequestView, NgoView }
import from crisisconnect.portal_api { ngo_requests, ngos }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.labels { plural }
import from ...components.app.page_parts { PageHero, EmptyNote, LoadingRows, IconChip }
import from .request_card { RequestCard }

def:pub GroupChooser(rows: list[NgoView], onPick: Callable[[str], None]) -> JsxElement {
    <div className="flex flex-col gap-4">
        <div>
            <h2 className="text-xl font-semibold tracking-tight">Choose your group</h2>
            <p className="text-sm text-muted-foreground">This browser remembers it. You can change it any time in the sidebar.</p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {for g in rows {
                <button
                    key={g.office}
                    type="button"
                    className="group flex items-center gap-4 rounded-xl border bg-card pt-4 pb-4 pl-4 pr-4 text-left transition-colors hover:bg-muted/50"
                    onClick={lambda (e: MouseEvent) { onPick(g.office); }}
                >
                    <IconChip icon={Building03Icon} tone="violet" />
                    <span className="min-w-0 flex-1">
                        <span className="block font-medium">{g.office}</span>
                        <span className="block text-sm text-muted-foreground">{", ".join(g.areas)}</span>
                        <span className="mt-1 block text-sm">{"Offers " + ", ".join(g.offers)}</span>
                    </span>
                    <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4 text-muted-foreground" />
                </button>
            }}
        </div>
    </div>
}

def:pub NgoRequestsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[RequestView] = [];
    has groups: list[NgoView] = [];
    has loaded: bool = False;
    has notice: str = "";

    async can with (ctx.tick, ctx.group) entry {
        try {
            if ctx.group == "" {
                groups = await ngos(ctx.tick);
                rows = [];
            } else {
                rows = await ngo_requests(ctx.group, ctx.tick);
            }
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    waiting: list[RequestView] = [r for r in rows if r.status == "REQUESTED" and r.ngo == ctx.group];
    vulnerable_n: int = len([r for r in waiting if len(r.vulnerable) > 0]);
    people_n: int = sum([r.headcount for r in waiting if r.headcount > 0]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow={"Relief group · " + (ctx.group if ctx.group != "" else "Requests")}
            title="Requests that need your answer."
            description="Division officers ask for help; CrisisConnect sends each request to the group best placed to supply it. Accept what you can deliver, or pass it on."
            image="/static/assets/images/volunteers-desk.jpg"
            imageAlt="Volunteers helping residents at a disaster recovery centre"
            capsules={[
                [plural(len(waiting), "request waiting", "requests waiting"), "amber"],
                [f"{vulnerable_n} with vulnerable people", "red"],
                [f"{people_n} people to reach", "blue"]
            ]}
        />
        {if notice != "" {
            <Alert>
                <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} />
                <AlertDescription>{notice}</AlertDescription>
            </Alert>
        }}
        {if ctx.group == "" and not loaded {
            <LoadingRows count={3} className="h-20" />
        } elif ctx.group == "" {
            <GroupChooser rows={groups} onPick={lambda (v: str) { ctx.setGroup(v); }} />
        } elif not loaded {
            <LoadingRows count={3} className="h-40" />
        } elif len(waiting) == 0 {
            <EmptyNote
                title="Nothing waiting for you"
                description="New requests that fit what your group offers appear here as soon as an officer asks."
                icon={InboxIcon}
            />
        } else {
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {for r in waiting {
                    <RequestCard key={r.req_id} r={r} group={ctx.group} onDone={lambda (msg: str) { notice = msg; ctx.bump(); }} />
                }}
            </div>
        }}
    </div>
}
