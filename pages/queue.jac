"""Call queue: every open incident, most urgent first, each with its reason."""

import from "@hugeicons/core-free-icons" { Call02Icon }
import type from ekata.views { QueueRow }
import from ekata.api { call_queue }
import from ..components.app.desk_state { use_desk }
import from ..components.app.items { QueueItem }
import from ..components.app.labels { plural }
import from ..components.app.page_parts { PageHero, EmptyNote, LoadingRows }

def:pub QueuePage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[QueueRow] = [];
    has loaded: bool = False;

    async def load(t: int) -> None {
        try {
            rows = await call_queue(t);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    async can with [ctx.tick] entry {
        await load(ctx.tick);
    }

    vulnerable_n: int = len([r for r in rows if len(r.vulnerable) > 0]);
    merged_n: int = len([r for r in rows if r.msg_count > 1]);
    people_n: int = sum([r.headcount for r in rows if r.headcount > 0]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Duty desk · Call queue"
            title="Who needs a call first."
            description="Open incidents ranked by risk, vulnerable people and waiting time. Every rank says why. Open an incident to see its evidence and log a call."
            image="/static/assets/images/boat-crossing.jpg"
            imageAlt="Rescue workers crossing flood water by boat"
            capsules={[
                [plural(len(rows), "open incident", "open incidents"), "blue"],
                [f"{vulnerable_n} with vulnerable people", "amber"],
                [f"{people_n} people reported", "green"],
                [f"{merged_n} merged from several reports", "violet"]
            ]}
        />
        {if not loaded {
            <LoadingRows count={5} className="h-28" />
        } elif len(rows) == 0 {
            <EmptyNote
                title="The queue is empty"
                description="Incidents appear here as messages arrive. Start the demo night from the header to see it fill."
                icon={Call02Icon}
            />
        } else {
            <ol className="flex flex-col gap-2">
                {for r in rows {
                    <QueueItem key={r.inc_id} row={r} />
                }}
            </ol>
        }}
    </div>
}
