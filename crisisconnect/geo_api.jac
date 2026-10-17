"""Map and route endpoints (all :pub, on the shared hub). See geo.jac."""

import from crisisconnect.store { get_hub }
import from crisisconnect.locking { graph_writer }
import from crisisconnect.portal { CitizenStatus, citizen_status }
import from crisisconnect.portal_api { citizen_send }
import from crisisconnect.geo {
    MapLayers, RoutePlan, NearbyPlace, map_layers_for, plan_for_division, plan_for_group,
    pin_report, nearby_shelters
}

def:pub map_layers(scope: str = "all", tick: int = 0) -> MapLayers {
    return map_layers_for(get_hub(), scope);
}

def:pub division_route(ds: str, max_stops: int = 5) -> RoutePlan {
    with graph_writer() {
        plan = plan_for_division(get_hub(), ds, int(max_stops) if max_stops else 5);
        commit();
        return plan;
    }
}

def:pub group_route(ngo: str, max_stops: int = 6) -> RoutePlan {
    with graph_writer() {
        plan = plan_for_group(get_hub(), ngo, int(max_stops) if max_stops else 6);
        commit();
        return plan;
    }
}

def:pub report_at(text: str, lat: float, lon: float) -> CitizenStatus {
    st = citizen_send(text, "WEB");
    if st.msg_id != "" and (lat != 0.0 or lon != 0.0) {
        with graph_writer() {
            hub = get_hub();
            pin_report(hub, st.msg_id, lat, lon);
            commit();
            st = citizen_status(hub, st.msg_id);
        }
    }
    return st;
}

def:pub shelters_near(lat: float, lon: float, tick: int = 0) -> list[NearbyPlace] {
    return nearby_shelters(lat, lon);
}
