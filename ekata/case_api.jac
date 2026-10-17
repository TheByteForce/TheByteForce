"""Case-lane endpoints: analyst decisions always go through the single writer."""
import from ekata.schema { Appeal, RumourClaim, Holds }
import from ekata.casework { AppealView, RumourView, CaseFile, Describes, find_appeal, review_appeal, appeal_view, rumour_view, r10_publish_allowed }
import from ekata.store { get_hub, log_decision }
import from ekata.locking { graph_writer }

def:pub appeals(tick: int = 0) -> list[AppealView] {
    hub = get_hub();
    return [appeal_view(hub, ap) for ap in [hub ->:Holds:->[?:Appeal]]];
}
def:pub appeal_detail(appeal_id: str, tick: int = 0) -> AppealView | None {
    hub = get_hub(); ap = find_appeal(hub, appeal_id);
    if ap is None { return None; }
    return appeal_view(hub, ap);
}
def:pub decide_appeal(appeal_id: str, desk: str, approve: bool) -> AppealView | None {
    with graph_writer() {
        hub = get_hub(); ap = find_appeal(hub, appeal_id);
        if ap is None { return None; }
        if desk.strip() == "" { raise ValueError("Choose an analyst desk."); }
        ap.approved_by = desk if approve else "";
        log_decision(hub, "analyst", "approve_verdict" if approve else "withdraw_approval", desk + " reviewed the cited evidence", "APPROVED" if approve else "UNAPPROVED", hub.storm_time, [ap], model="human", target_label=appeal_id);
        commit();
        return appeal_view(hub, ap);
    }
}
def:pub investigate_appeal(appeal_id: str) -> AppealView | None {
    with graph_writer() {
        hub = get_hub(); ap = find_appeal(hub, appeal_id);
        if ap is None { return None; }
        view = review_appeal(hub, ap, True); commit(); return view;
    }
}
def:pub rumour_log(tick: int = 0) -> list[RumourView] {
    hub = get_hub();
    return [rumour_view(hub, x) for x in [hub ->:Holds:->[?:RumourClaim]]];
}


import from ekata.ai.brief { CallBrief, read_brief, generate_brief }
import from ekata.ai.triage { explain_top }
import from ekata.coordinator { build_queue }
import from ekata.views { QueueRow }
import from ekata.store { find_incident }

def:pub call_brief(inc_id: str, tick: int = 0) -> CallBrief | None {
    hub = get_hub(); inc = find_incident(hub, inc_id);
    if inc is None { return None; }
    return read_brief(hub, inc);
}
def:pub refresh_call_brief(inc_id: str) -> CallBrief | None {
    with graph_writer() {
        hub = get_hub(); inc = find_incident(hub, inc_id);
        if inc is None { return None; }
        result = generate_brief(hub, inc); commit(); return result;
    }
}
def:pub explain_queue() -> list[QueueRow] {
    with graph_writer() {
        hub = get_hub(); result = explain_top(hub, build_queue(hub)); commit(); return result;
    }
}


def:pub published_appeals(tick: int = 0) -> list[AppealView] {
    hub = get_hub();
    return [appeal_view(hub, ap) for ap in [hub ->:Holds:->[?:Appeal]] if r10_publish_allowed(ap.approved_by)];
}
