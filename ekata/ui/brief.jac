import type from ekata.ai.brief { CallBrief }
import from ekata.case_api { call_brief, refresh_call_brief }
import from ...components.ui.button { Button }

def:pub BriefPanel(incId: str) -> JsxElement {
    has brief: CallBrief | None = None;
    has busy: bool = False;
    has error: str = "";
    async can with entry {
        brief = await call_brief(incId, 0);
    }
    async def generate -> None {
        busy = True;
        try {
            brief = await refresh_call_brief(incId);
            error = "";
        } except Exception as e {
            error = str(e);
        }
        busy = False;
    }
    <section aria-label="Call brief">
        <div className="flex items-center justify-between gap-2">
            <p className="text-[13px] text-muted-foreground">Questions drafted from what we know so far.</p>
            <Button
                variant="outline"
                size="sm"
                disabled={busy}
                onClick={lambda (e: MouseEvent) { generate(); }}
            >
                {"Preparing..." if busy else "Prepare questions"}
            </Button>
        </div>
        {if error != "" {
            <p role="alert" className="mt-2 text-[13px] text-blocked">{error}</p>
        }}
        {if brief is not None {
            <div className="mt-2 rounded-lg bg-muted p-4 text-[15px]">
                {if len(brief.known) > 0 {
                    <div>
                        <p className="text-[13px] text-muted-foreground">
                            What we know
                        </p>
                        <ul className="mt-1 list-disc space-y-0.5 pl-5">
                            {for x in brief.known {
                                <li key={x}>{x}</li>
                            }}
                        </ul>
                    </div>
                }}
                {for x in brief.missing {
                    <p key={x} className="mt-2">
                        <span className="font-semibold">Still missing: </span>
                        {x}
                    </p>
                }}
                {for x in brief.contradictions {
                    <p key={x} className="mt-2">
                        <span className="font-semibold">Check this: </span>
                        {x}
                    </p>
                }}
                {if len(brief.questions) > 0 {
                    <div className="mt-3">
                        <p className="text-[13px] text-muted-foreground">
                            Questions
                        </p>
                        <ol className="mt-1 list-decimal space-y-1.5 pl-5">
                            {for q in brief.questions {
                                <li key={q}>{q}</li>
                            }}
                        </ol>
                    </div>
                }}
            </div>
        }}
    </section>
}
