import from ekata.api {
    load_demo,
    demo_state,
    replay_next,
    submit_message,
    call_queue,
    incident_detail,
    decide_merge,
    log_call,
    trace_since,
    metrics,
    recent_messages,
    claim_incident,
    resolve_change
}

import from ekata.ui.desk { Desk }
import from ekata.ui.cases { Cases }
import from ekata.case_api {
    appeals,
    appeal_detail,
    decide_appeal,
    investigate_appeal,
    rumour_log,
    call_brief,
    refresh_call_brief,
    explain_queue,
    published_appeals
}
import ".styles.global.css";

import from ekata.ui.metrics { MetricsPage }
import from ekata.evaluation_api { evaluation_results, model_usage }

def:pub app() -> JsxElement {
    has page: str = "desk";
    can with entry {
        document.title = "Ekata · Flood response desk";
    }
    <div className="min-h-screen bg-background text-foreground">
        <nav
            aria-label="Workspace"
            className="flex min-h-16 flex-wrap items-center gap-3 border-b bg-card px-4 py-2 lg:px-6"
        >
            <div className="mr-3 flex items-center gap-2.5">
                <span
                    className="flex size-9 items-center justify-center rounded-xl bg-primary text-lg font-bold text-primary-foreground"
                >
                    E
                </span>
                <div>
                    <strong className="block text-base leading-tight">Ekata</strong>
                    <span className="hidden text-xs text-muted-foreground sm:block">
                        Flood response workspace
                    </span>
                </div>
            </div>
            <div className="flex gap-1 rounded-lg bg-muted p-1">
                <button
                    className={"rounded-md px-3 py-2 text-sm font-semibold transition-colors "
                        + (
                            "bg-background text-foreground shadow-sm"
                                if page == "desk"
                                else "text-muted-foreground hover:text-foreground"
                        )}
                    aria-current={"page" if page == "desk" else "false"}
                    onClick={lambda (e: MouseEvent) { page = "desk"; }}
                >
                    Rescue desk
                </button>
                <button
                    className={"rounded-md px-3 py-2 text-sm font-semibold transition-colors "
                        + (
                            "bg-background text-foreground shadow-sm"
                                if page == "cases"
                                else "text-muted-foreground hover:text-foreground"
                        )}
                    aria-current={"page" if page == "cases" else "false"}
                    onClick={lambda (e: MouseEvent) { page = "cases"; }}
                >
                    Appeals & rumours
                </button>
            </div>
            <span
                className="ml-auto rounded-full border border-amber-300 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-900"
            >
                Synthetic data
            </span>
            <button className={"rounded-md border px-3 py-2 text-sm font-semibold " + ("bg-primary text-primary-foreground" if page == "metrics" else "text-muted-foreground")} onClick={lambda (e: MouseEvent) { page = "metrics"; }}>Impact & evaluation</button>
        </nav>
        {if page == "desk" { <Desk />; } elif page == "cases" { <Cases />; } else { <MetricsPage />; }}
    </div>
}
