"""CrisisConnect entry point: registers every server endpoint and mounts the
file-based routes in pages/ (the shell is pages/layout.jac).

Each person works in one portal: /citizen, /officer, /ngo or /district.
The situation runs live: crisisconnect.live_feed brings reports in as time passes.
"""

import from crisisconnect.api {
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
import from crisisconnect.live_feed { situation_pulse }
import from crisisconnect.coordination_api {
    alert_levels, set_alert_override, volunteer_offers, appeal_verdicts, run_appeal_checks, ds_handover, ds_divisions
}
import from crisisconnect.memory_api { agent_run, rule_stats, precedent_stats }
import from crisisconnect.scenario_api { scenario_reset, scenario_next, scenario_state }
import from crisisconnect.geo_api { map_layers, division_route, group_route, report_at, shelters_near }
import from crisisconnect.case_api {
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
import from crisisconnect.evaluation_api { evaluation_results, model_usage }
import from crisisconnect.gn_register_api { gn_areas, gn_register, setup_gn_register, open_gn_register }
import from crisisconnect.portal_api {
    divisions,
    officer_queue,
    set_gn,
    resource_kinds,
    request_resource,
    incident_requests,
    ngos,
    registry,
    ngo_requests,
    all_requests,
    respond_request,
    citizen_send,
    track_request,
    bulletins,
    publish_bulletin,
    escalations,
    district_board,
    household_timeline
}

import ".styles.global.css";
import ".styles.app.css";

# File-based routing: pages/ supplies the routes and pages/layout.jac the shell.
def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
