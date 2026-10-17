import from ekata.api {
    load_demo, demo_state, replay_next, submit_message, call_queue,
    incident_detail, decide_merge, log_call, trace_since, metrics, inbox_messages
}
import from ekata.coordination_api {
    alert_levels, volunteer_offers, appeal_verdicts, run_appeal_checks, ds_handover, ds_divisions
}

import ".styles.global.css";

# File-based routing: pages/ supplies the routes and pages/layout.jac the shell.
def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
