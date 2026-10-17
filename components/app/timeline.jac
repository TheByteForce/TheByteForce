import type from ekata.timeline { HouseholdTimeline }
import from ekata.portal_api { household_timeline }
import from .desk_state { use_desk }

def:pub HouseholdStory(incId: str) -> JsxElement {
    ctx: any = use_desk();
    has story: HouseholdTimeline | None = None;
    has error: str = "";
    async can with (incId, ctx.tick) entry {
        try { story = await household_timeline(incId, ctx.tick); error = ""; }
        except Exception as ex { error = str(ex); }
    }
    <section className="rounded-xl border bg-card p-5">
        <div className="flex flex-wrap justify-between gap-2"><h2 className="text-xl font-semibold">One verified household</h2><a className="text-sm font-semibold text-primary" href="/graph" target="_blank" rel="noreferrer">Open live Jac graph</a></div>
        {if error != "" { <p role="alert">{error}</p> }}
        {if story is not None { <div>
            <p className="mt-3 text-sm leading-relaxed">{story.record}</p>
            <ol className="mt-5 space-y-4">{for event in story.steps {
                <li key={str(event.seq)} className="border-l-2 pl-4">
                    <p className="text-xs text-muted-foreground">{event.time + " · " + event.stage + " · " + event.actor}</p>
                    <h3 className="mt-1 font-semibold">{event.title}</h3><p className="mt-1 text-sm">{event.detail}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{event.outcome + (" · " + event.model if event.model != "" else "")}</p>
                </li>
            }}</ol>
        </div> }}
    </section>
}
