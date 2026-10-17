"""Ekata entry point: serves every endpoint and routes each person to their portal.

Each person uses one portal, reached by its own address:
  #/citizen   people in the flood and their families
  #/officer   division officers (Grama Niladhari / divisional desks)
  #/ngo       registered relief groups
  #/district  district coordination
There are no links between portals. ?ops adds the hidden operator panel used
to replay the synthetic storm night for the demo.
"""

import from "react" { useEffect }
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
import from ekata.coordination_api {
    alert_levels, set_alert_override, volunteer_offers, appeal_verdicts, run_appeal_checks, ds_handover, ds_divisions
}
import from ekata.memory_api { agent_run, rule_stats, precedent_stats }
import from ekata.geo_api { map_layers, division_route, group_route, report_at, shelters_near }
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
import from ekata.evaluation_api { evaluation_results, model_usage }
import from ekata.portal_api {
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

import from ekata.ui.home { Home }
import from ekata.ui.citizen { CitizenPortal }
import from ekata.ui.officer { OfficerPortal }
import from ekata.ui.ngo { NgoPortal }
import from ekata.ui.district { DistrictPortal }
import from ekata.ui.ops { OpsPanel }

def:pub app() -> JsxElement {
    has route: str = "";
    has ops: bool = False;

    # Kept inline: a def:pub helper becomes a server endpoint, and a plain
    # helper here is not placed on the client.
    def read_route -> None {
        h = window.location.hash.replace("#", "").replace("/", "").lower();
        route = h if h in ["citizen", "officer", "ngo", "district"] else "";
    }

    can with entry {
        read_route();
        ops = "ops" in window.location.search;
        document.title = "Ekata";
    }

    useEffect(
        lambda {
            handler = lambda { read_route(); window.scrollTo(0, 0); };
            window.addEventListener("hashchange", handler);
            return lambda { window.removeEventListener("hashchange", handler); };
        },
        []
    );

    <div className="min-h-screen bg-background text-foreground">
        {if route == "citizen" {
            <CitizenPortal/>;
        } elif route == "officer" {
            <OfficerPortal/>;
        } elif route == "ngo" {
            <NgoPortal/>;
        } elif route == "district" {
            <DistrictPortal/>;
        } else {
            <Home/>;
        }}
        {if ops {
            <OpsPanel/>
        }}
    </div>
}
