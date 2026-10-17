"""Call queue: every open incident, most urgent first, each with its reason."""

import from "@hugeicons/core-free-icons" { Call02Icon }
import type from ekata.views { QueueRow }
import from ekata.api { call_queue }
import from ..components.app.desk_state { use_desk }
import from ..components.app.items { QueueItem }
import from ..components.app.labels { plural }
import from ..components.app.page_parts { PageHeader, EmptyNote, LoadingRows }

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

    <div className="flex flex-col gap-6">
        <PageHeader
            title="Call queue"
            description="Open incidents ranked by who needs a call first. Every rank says why. Open an incident to see its evidence and log a call."
            image="/static/assets/images/boat-crossing.jpg"
            imageAlt="Rescue workers crossing flood water by boat"
        />
        <p className="text-sm text-muted-foreground">{plural(len(rows), "open incident", "open incidents")}</p>
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
