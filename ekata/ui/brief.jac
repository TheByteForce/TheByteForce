import from ekata.ai.brief { CallBrief }
import from ekata.case_api { call_brief, refresh_call_brief }
import from ...components.ui.button { Button }

def:pub BriefPanel(incId: str) -> JsxElement {
    has brief: CallBrief | None = None;
    has busy: bool = False;
    has error: str = "";
    async can with entry { brief = await call_brief(incId, 0); }
    async def generate -> None {
        busy = True;
        try { brief = await refresh_call_brief(incId); error = ""; }
        except Exception as e { error = str(e); }
        busy = False;
    }
    <section className="mt-4 rounded border bg-muted/30 p-3" aria-label="Call brief">
        <div className="flex items-center justify-between gap-2"><h3 className="font-semibold">One-call brief</h3><Button variant="outline" disabled={busy} onClick={lambda (e: MouseEvent) { generate(); }}>{"Preparing..." if busy else "Prepare with AI"}</Button></div>
        {if error != "" { <p role="alert">{error}</p> }}
        {if brief is not None {
            <div><p className="mt-2 text-xs text-muted-foreground">{brief.model}</p>
            <ul className="mt-2 text-sm">{for x in brief.known { <li key={x}>{x}</li> }}</ul>
            {for x in brief.missing { <p key={x} className="mt-1 text-sm"><strong>Missing: </strong>{x}</p> }}
            {for x in brief.contradictions { <p key={x} className="mt-1 text-sm text-amber-800"><strong>Verify: </strong>{x}</p> }}
            <ol className="mt-3 list-decimal space-y-2 pl-5">{for q in brief.questions { <li key={q}>{q}</li> }}</ol></div>
        }}
    </section>
}
