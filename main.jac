import from ekata.api {
    load_demo, demo_state, replay_next, submit_message, call_queue,
    incident_detail, decide_merge, log_call, trace_since, metrics, recent_messages, claim_incident, resolve_change
}

import from ekata.ui.desk { Desk }
import from ekata.ui.cases { Cases }
import from ekata.case_api { appeals, appeal_detail, decide_appeal, investigate_appeal, rumour_log, call_brief, refresh_call_brief, explain_queue, published_appeals }
import ".styles.global.css";

def:pub app() -> JsxElement {
    has page: str = "desk";
    <div className="min-h-screen bg-background text-foreground">
        <nav aria-label="Workspace" className="flex gap-2 border-b bg-card px-5 py-2">
            <button className="rounded border px-4 py-2 font-semibold" aria-pressed={page == "desk"} onClick={lambda (e: MouseEvent) { page = "desk"; }}>Rescue desk</button>
            <button className="rounded border px-4 py-2 font-semibold" aria-pressed={page == "cases"} onClick={lambda (e: MouseEvent) { page = "cases"; }}>Appeals & rumours</button>
        </nav>
        {if page == "desk" { <Desk />; } else { <Cases />; }}
    </div>
}
