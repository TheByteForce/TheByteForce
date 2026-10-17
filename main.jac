import from ekata.api {
    load_demo, demo_state, replay_next, submit_message, call_queue,
    incident_detail, decide_merge, log_call, trace_since, metrics
}
import from ekata.coordination_api {
    alert_levels, volunteer_offers, appeal_verdicts, run_appeal_checks, ds_handover, ds_divisions
}

import from ekata.ui.desk { Desk }
import ".styles.global.css";

def:pub app() -> JsxElement {
    return <Desk />;
}
