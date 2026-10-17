"""Role portal endpoints (all :pub, on the shared hub). See portal.jac.

Each person uses one portal: citizen, officer (one DS division), NGO (one
registered group) or district. Readers take a tick so the 60 s client cache
never hides new data.
"""

import from ekata.store { get_hub }
import from ekata.locking { graph_writer }
import from ekata.views { QueueRow }
import from ekata.casework { refresh_appeals }
import from ekata.api { submit_message }
import from ekata.portal {
    DivisionView, RequestView, NgoView, BulletinView, CitizenStatus, EscalationRow, DistrictOverview,
    division_views, officer_rows, pin_gn, create_request, request_view, requests_of, answer_request,
    ngo_views, requests_for_ngo, all_request_views, bulletin_views, add_bulletin, citizen_status,
    escalation_rows, district_overview, RESOURCE_KINDS
}
import from ekata.store { find_incident }

def:pub divisions(tick: int = 0) -> list[DivisionView] {
    return division_views(get_hub());
}

def:pub officer_queue(ds: str, tick: int = 0) -> list[QueueRow] {
    return officer_rows(get_hub(), ds);
}

def:pub set_gn(inc_id: str, gn: str, officer: str) -> bool {
    with graph_writer() {
        ok = pin_gn(get_hub(), inc_id, gn, officer);
        commit();
        return ok;
    }
}

def:pub resource_kinds() -> list[str] {
    return RESOURCE_KINDS;
}

def:pub request_resource(inc_id: str, need: str, officer: str) -> RequestView | None {
    with graph_writer() {
        hub = get_hub();
        req = create_request(hub, inc_id, need, officer);
        commit();
        return request_view(hub, req) if req is not None else None;
    }
}

def:pub incident_requests(inc_id: str, tick: int = 0) -> list[RequestView] {
    hub = get_hub();
    inc = find_incident(hub, inc_id);
    if inc is None {
        return [];
    }
    return [request_view(hub, r) for r in requests_of(inc)];
}

def:pub ngos(tick: int = 0) -> list[NgoView] {
    return ngo_views(get_hub(), "NGO");
}

def:pub registry(tick: int = 0) -> list[NgoView] {
    return ngo_views(get_hub(), "");
}

def:pub ngo_requests(ngo: str, tick: int = 0) -> list[RequestView] {
    return requests_for_ngo(get_hub(), ngo);
}

def:pub all_requests(tick: int = 0) -> list[RequestView] {
    return all_request_views(get_hub());
}

def:pub respond_request(req_id: str, ngo: str, action: str) -> RequestView | None {
    with graph_writer() {
        hub = get_hub();
        req = answer_request(hub, req_id, ngo, action);
        commit();
        return request_view(hub, req) if req is not None else None;
    }
}

def:pub citizen_send(text: str, channel: str = "SMS") -> CitizenStatus {
    step = submit_message(text, channel);
    hub = get_hub();
    mid = step.message.msg_id if step.message is not None else "";
    if step.message is not None and step.message.kind in ["APPEAL", "RUMOUR"] {
        with graph_writer() {
            refresh_appeals(hub);
            commit();
        }
    }
    return citizen_status(hub, mid);
}

def:pub track_request(msg_id: str, tick: int = 0) -> CitizenStatus {
    return citizen_status(get_hub(), msg_id.strip());
}

def:pub bulletins(area: str = "", tick: int = 0) -> list[BulletinView] {
    return bulletin_views(get_hub(), area);
}

def:pub publish_bulletin(issuer: str, area: str, text: str) -> BulletinView {
    with graph_writer() {
        if text.strip() == "" { raise ValueError("Write the bulletin text first."); }
        b = add_bulletin(get_hub(), issuer, area, text);
        commit();
        return b;
    }
}

def:pub escalations(tick: int = 0) -> list[EscalationRow] {
    return escalation_rows(get_hub());
}

def:pub district_board(tick: int = 0) -> DistrictOverview {
    return district_overview(get_hub());
}
