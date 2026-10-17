"""The guided demonstration: one household, seven checkpoints.

Each step runs the real pipeline (intake, resolver, referee, matcher, appeal
lane) on the shared hub, then says what to show and where. Nothing is faked:
the steps only supply the messages and the human actions a desk would take.
All names, places and numbers are invented.
"""

import from crisisconnect.schema { CrisisConnectHub, Holds, Message }
import from crisisconnect.store { get_hub, next_msg_id, find_message, incident_of }
import from crisisconnect.seed { reset_and_seed }
import from crisisconnect.coordinator { process_in_hub, record_call }
import from crisisconnect.portal { create_request, answer_request, find_request }
import from crisisconnect.geo { pin_report }
import from crisisconnect.casework { refresh_appeals }

node ScenarioState {
    has step: int = 0;
    has inc_id: str = "";
    has other_id: str = "";
    has ref: str = "";
    has req_id: str = "";
    has first_group: str = "";
}

obj ScenarioStep {
    has n: int;
    has title: str;
    has show: str;
}

obj ScenarioView {
    has step: int = 0;
    has total: int = 7;
    has done: bool = False;
    has title: str = "";
    has show: str = "";
    has happened: str = "";
    has inc_id: str = "";
    has ref: str = "";
    has steps: list[ScenarioStep] = [];
}

glob DESK: str = "Divisional desk, Mawanella";

glob STEPS: list[ScenarioStep] = [
    ScenarioStep(n=1, title="Two people report the same household", show="Officer portal, Mawanella: one household with 2 messages merged. Open it and read the household story."),
    ScenarioStep(n=2, title="A different family with the same surname", show="Still two cases: another Perera at another address stays separate. The merge safety check is in the story."),
    ScenarioStep(n=3, title="The officer calls the household", show="Citizen portal, track the reference: 'Officer confirmed by phone'. The first, unanswered call did not count."),
    ScenarioStep(n=4, title="A boat is requested and the first group declines", show="Relief group portal: the first group declined; CrisisConnect sent the request to the next eligible group."),
    ScenarioStep(n=5, title="The second group accepts and sets off", show="Citizen tracker: 'Help is on the way'. Relief group map: plan the run from its base."),
    ScenarioStep(n=6, title="Two appeals name this household", show="District, Appeals: the appeal through a registered group matches the verified household; the one asking for an OTP is flagged."),
    ScenarioStep(n=7, title="Delivery closes the loop", show="Citizen tracker: Help delivered. Show the household story from first SOS to delivery and appeals, then the live Jac graph and Results.")
];

def state_of(hub: CrisisConnectHub) -> ScenarioState {
    found = [hub ->:Holds:->[?:ScenarioState]];
    if len(found) > 0 {
        return found[0];
    }
    st = ScenarioState();
    hub +>:Holds:+> st;
    return st;
}

def view_of(st: ScenarioState, happened: str) -> ScenarioView {
    cur = STEPS[st.step - 1] if st.step >= 1 and st.step <= len(STEPS) else None;
    nxt = STEPS[st.step] if st.step < len(STEPS) else None;
    return ScenarioView(
        step=st.step, total=len(STEPS), done=st.step >= len(STEPS),
        title=cur.title if cur is not None else (nxt.title if nxt is not None else ""),
        show=cur.show if cur is not None else "Press Next to start the story.",
        happened=happened, inc_id=st.inc_id, ref=st.ref, steps=STEPS
    );
}

def say(hub: CrisisConnectHub, text: str, channel: str, t: str) -> Message {
    hub.storm_time = t;
    return process_in_hub(hub, text, channel, t, next_msg_id(hub));
}

def at(hub: CrisisConnectHub, t: str) {
    hub.storm_time = t;
}

def scenario_reset_in(hub: CrisisConnectHub) -> ScenarioView {
    reset_and_seed(hub);
    st = state_of(hub);
    return view_of(st, "A clean storm night is ready. No messages yet.");
}

def scenario_next_in(hub: CrisisConnectHub) -> ScenarioView {
    st = state_of(hub);
    n = st.step + 1;
    happened = "";
    if n == 1 {
        m1 = say(hub, "Help! This is Nimal Perera. Water is up to the roof at 12 Temple Road, Mawanella. 5 of us here, my grandmother cannot walk. Call 07X-555-0142", "SMS", "18:05");
        pin_report(hub, m1.msg_id, 7.2546, 80.4471);
        say(hub, "Please send a boat to no 12 temple rd mawanella, my mother and family are stuck. Nimal Perera phone 07X5550142", "WHATSAPP", "18:12");
        inc = incident_of(m1);
        st.inc_id = inc.inc_id if inc is not None else "";
        st.ref = m1.msg_id;
        happened = f"An SMS and a WhatsApp from a relative arrived. The resolver merged them into {st.inc_id}; citizen reference {st.ref}.";
    } elif n == 2 {
        m3 = say(hub, "Kamal Perera here, 3 people at 40 Kandy Road Mawanella, water rising fast. Call 07X-555-0177", "SMS", "18:15");
        other = incident_of(m3);
        st.other_id = other.inc_id if other is not None else "";
        happened = f"Same surname, different address and phone: kept as {st.other_id}, not merged into {st.inc_id}.";
    } elif n == 3 {
        at(hub, "18:25");
        record_call(hub, st.inc_id, "NO_ANSWER", DESK, "Line busy");
        at(hub, "18:32");
        record_call(hub, st.inc_id, "REACHED_CONFIRMED", DESK, "Spoke to Nimal: 5 people, grandmother cannot walk");
        happened = "18:25 no answer (household stays unverified). 18:32 reached and confirmed: the household is now verified.";
    } elif n == 4 {
        at(hub, "18:40");
        req = create_request(hub, st.inc_id, "boat", DESK);
        if req is not None {
            st.req_id = req.req_id;
            st.first_group = req.ngo;
            at(hub, "18:44");
            answer_request(hub, req.req_id, req.ngo, "decline");
            happened = f"Boat request {req.req_id} went to {st.first_group}, who declined. CrisisConnect re-routed it to {req.ngo}.";
        } else {
            happened = "The request could not be created.";
        }
    } elif n == 5 {
        req = find_request(hub, st.req_id);
        if req is not None {
            at(hub, "18:50");
            answer_request(hub, req.req_id, req.ngo, "accept");
            at(hub, "18:58");
            answer_request(hub, req.req_id, req.ngo, "dispatched");
            happened = f"{req.ngo} accepted at 18:50 and set off at 18:58.";
        }
    } elif n == 6 {
        say(hub, "Donate for Nimal Perera's family at 12 Temple Road Mawanella, 5 people. Relief through Hill Country Relief Trust 07X-555-0911", "WHATSAPP", "19:10");
        say(hub, "URGENT help Nimal Perera family at 12 Temple Road Mawanella, they need money now. Send to account SYN-XXXX-9999 and reply with the OTP you receive", "WHATSAPP", "19:14");
        refresh_appeals(hub);
        happened = "Two appeals arrived. Each was checked against the verified household and the registry.";
    } elif n == 7 {
        req = find_request(hub, st.req_id);
        if req is not None {
            at(hub, "19:25");
            answer_request(hub, req.req_id, req.ngo, "delivered");
        }
        happened = "The relief group recorded delivery at 19:25. The citizen sees Help delivered; the verified household record retains the complete evidence trail.";
    } else {
        return view_of(st, "The story is complete. Reset to run it again.");
    }
    st.step = n;
    return view_of(st, happened);
}

def scenario_state_in(hub: CrisisConnectHub) -> ScenarioView {
    return view_of(state_of(hub), "");
}
