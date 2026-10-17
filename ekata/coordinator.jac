"""Coordinator: the single writer of the Ekata graph.

One message in, one ordered pass out. process_in_hub extracts a typed report
(intake), writes the Message and its identifier nodes, finds candidate
incidents (blocking), lets the resolver choose, lets the referee check the
choice (with one retry on a block), then attaches the message to an incident
and runs freshness and priority. Every step is recorded as a Decision.

Also here, so the endpoints in api.jac stay thin and tests can run on a
private hub: the queue, incident and trace builders, the desk's merge
decision and the call log.

AI switch: set EKATA_AI=off to skip the LLM calls. Intake then uses the rules
extractor below and the resolver is replaced by a rules pick over the
blocking tiers. The same path is the fallback when an LLM call fails.
"""

import os;
import from ekata.schema {
    EkataHub,
    Holds,
    About,
    Message,
    Phone,
    PersonName,
    Place,
    Incident,
    CallLog,
    Decision,
    Appeal,
    BankAccount,
    Url,
    ClaimedOfficial,
    RumourClaim,
    GNDivision,
    DSDivision,
    HasPhone,
    Names,
    At,
    Candidate,
    PartOf,
    Logged,
    LocatedIn,
    InDS,
    PaysTo,
    AppealHasPhone,
    Links,
    ClaimsToBe,
    SosReport,
    PersonMention,
    MsgKind,
    PlaceLevel,
    RefereeOutcome
}
import from ekata.views {
    MsgView,
    QueueRow,
    CandidateView,
    ProposalView,
    CallView,
    TraceRow,
    IncidentView,
    ReplayStep,
    Metrics, ChangeView
}
import from ekata.store {
    MergeProposal,
    get_hub,
    next_msg_id,
    next_incident_id,
    next_message_seq,
    all_incidents,
    all_messages,
    find_message,
    find_incident,
    messages_of,
    incident_of,
    change_status,
    all_proposals,
    storm_minutes,
    storm_diff,
    fmt_minutes,
    advance_clock,
    normalise_phone,
    phones_in_text,
    normalise_name,
    normalise_place,
    area_level,
    household_display,
    ensure_phone,
    ensure_person,
    ensure_area,
    ensure_household,
    log_decision, open_pending
}
import from ekata.seed { ensure_seeded }
import from ekata.fixtures { peek_next }
import from ekata.blocking {
    CandInfo,
    find_candidates,
    tier_of,
    in_candidates,
    best_strong,
    annotate_candidate
}
import from ekata.freshness { Facts, apply_facts }
import from ekata.priority { refresh_priority, priority_now }
import from ekata.referee { referee_merge, r5_claim, OPEN_STATUSES }
import from ekata.ai.intake { extract_report, extract_report_rules, intake_run_info }
import from ekata.ai.resolver { Resolver }
import from ekata.ai.triage { overlay_rank }
import from ekata.casework { refresh_appeals, link_bulletins, CredentialRequest, Asks }

# ---------- AI switch ----------

def ai_enabled() -> bool {
    return os.environ.get("EKATA_AI", "on").lower() != "off";
}

# ---------- Intake (LLM first, rules fallback) ----------

obj IntakeOutcome {
    has rep: SosReport;
    has model: str = "rules";
    has note: str = "";
}

# The intake agent's rules extractor; a bare SOS report if even that fails.
def rules_report(text: str, channel: str) -> SosReport {
    try {
        return extract_report_rules(text, channel);
    } except Exception as e {
        return SosReport(
            kind=MsgKind.SOS, summary=text[:80], phones=phones_in_text(text)
        );
    }
}

def run_intake(text: str, channel: str) -> IntakeOutcome {
    if ai_enabled() {
        try {
            rep = extract_report(text, channel);
            info = intake_run_info();
            engine = info.get("engine", "llm");
            model = info.get("model", "");
            return IntakeOutcome(
                rep=rep,
                model=model if model != "" else engine,
                note=""
                    if engine == "llm"
                    else ("Cached output recorded at " + info.get("recorded_at", "unknown") if engine == "cached" else "LLM unavailable: the intake rules extractor was used")
            );
        } except Exception as e {
            return IntakeOutcome(
                rep=rules_report(text, channel),
                model="rules",
                note="LLM intake failed (" + str(e)[:60] + "): rules extractor used"
            );
        }
    }
    return IntakeOutcome(
        rep=rules_report(text, channel),
        model="rules",
        note="AI switched off: rules extractor used"
    );
}

# ---------- Decisions ----------

# Log one pipeline step about the message and remember it, so the finished
# incident can be linked to every step once it is known.
def step(
    hub: EkataHub,
    decs: list[Decision],
    msg: Message,
    agent: str,
    action: str,
    reason: str,
    outcome: str,
    t: str,
    conf: float = 1.0,
    model: str = "rules",
    label: str = ""
) -> Decision {
    d = log_decision(
        hub,
        agent,
        action,
        reason,
        outcome,
        t,
        [msg],
        confidence=conf,
        model=model,
        target_label=label if label != "" else msg.msg_id
    );
    decs.append(d);
    return d;
}

# ---------- Identifier nodes ----------

def attach_identifiers(hub: EkataHub, msg: Message, rep: SosReport) -> list[str] {
    phones: list[str] = [];
    for raw in rep.phones + phones_in_text(msg.text) {
        canon = normalise_phone(raw);
        if canon != "" and canon not in phones {
            phones.append(canon);
        }
    }
    for canon in phones {
        msg +>:HasPhone:+> ensure_phone(hub, canon);
    }
    seen: list[str] = [];
    for pm in rep.names {
        canon = normalise_name(pm.canonical if pm.canonical != "" else pm.display);
        if canon == "" or canon in seen {
            continue;
        }
        seen.append(canon);
        msg +>:Names:+> ensure_person(hub, canon, pm.display);
    }
    if rep.house_ref != "" {
        msg +>:At:+> ensure_household(hub, rep.house_ref, rep.place_text);
    }
    area = normalise_place(rep.place_text);
    if area != "" {
        msg +>:At:+> ensure_area(hub, area, area_level(rep.place_text));
    }
    return phones;
}

def place_display(rep: SosReport) -> str {
    where = rep.place_text;
    if rep.house_ref != "" and rep.house_ref not in where {
        label = ("No. " + rep.house_ref)
            if rep.house_ref[0].isdigit()
            else rep.house_ref;
        where = (label + ", " + where) if where != "" else label;
    }
    return where;
}

# The GN division placeholder of the DS division named in the text (if any).
def gn_for_place(hub: EkataHub, place_text: str, text: str) -> GNDivision | None {
    for hay in [place_text.lower(), text.lower()] {
        best_ds: DSDivision | None = None;
        best_idx = -1;
        for ds in [hub->:Holds:->[?:DSDivision]] {
            idx = hay.find(ds.name.lower()[:6]);
            if idx >= 0 and (best_idx < 0 or idx < best_idx) {
                best_idx = idx;
                best_ds = ds;
            }
        }
        if best_ds is not None {
            for gn in [best_ds<-:InDS:<-[?:GNDivision]] {
                if gn.name.endswith("(GN not stated)") {
                    return gn;
                }
            }
        }
    }
    return None;
}

def new_incident(hub: EkataHub, rep: SosReport, text: str, t: str) -> Incident {
    inc = Incident(
        inc_id=next_incident_id(hub), status="NEW", first_seen=t, last_seen=t
    );
    hub +>:Holds:+> inc;
    gn = gn_for_place(hub, rep.place_text, text);
    if gn is not None {
        inc +>:LocatedIn:+> gn;
        inc.gn = gn.name;
    }
    return inc;
}

# ---------- Resolving ----------

obj Pick {
    has chosen: str = "";
    has score: float = 0.0;
    has reason: str = "";
    has model: str = "rules";
}

# Spawn the Resolver walker on the message; None when it cannot run.
def run_resolver(msg: Message, block_reason: str) -> Resolver | None {
    try {
        r = Resolver();
        if block_reason != "" and hasattr(r, "block_reason") {
            setattr(r, "block_reason", block_reason);
        }
        walked = msg spawn r;
        return walked;
    } except Exception as e {
        return None;
    }
}

# Rules stand-in for the resolver: STRONG first, then the first MEDIUM
# (proposed to a person by the referee), never a WEAK one.
def rules_pick(infos: list[CandInfo], why: str) -> Pick {
    strong = best_strong(infos);
    if strong is not None {
        return Pick(
            chosen=strong.inc_id,
            score=0.9,
            model="rules",
            reason=why + "strong evidence: " + ", ".join(strong.reasons)
        );
    }
    for c in infos {
        if c.tier == "MEDIUM" {
            return Pick(
                chosen=c.inc_id,
                score=0.6,
                model="rules",
                reason=why + "partial evidence only: " + ", ".join(c.reasons)
            );
        }
    }
    return Pick(
        chosen="",
        score=0.0,
        model="rules",
        reason=why + "no candidate with enough shared detail"
    );
}

def resolve_pick(
    msg: Message, infos: list[CandInfo], block_reason: str, use_ai: bool
) -> Pick {
    why = "";
    if use_ai {
        walked = run_resolver(msg, block_reason);
        if walked is not None {
            if walked.chosen_inc_id != "" or walked.model != "" {
                return Pick(
                    chosen=walked.chosen_inc_id,
                    score=walked.score,
                    reason=walked.reason,
                    model=walked.model if walked.model != "" else "llm"
                );
            }
            why = "resolver gave no decision, rules fallback: ";
        } else {
            why = "resolver unavailable, rules fallback: ";
        }
    }
    return rules_pick(infos, why);
}

def ensure_candidate_edges(hub: EkataHub, msg: Message, infos: list[CandInfo]) {
    for info in infos {
        inc = find_incident(hub, info.inc_id);
        if inc is not None and len([edge msg->:Candidate:->inc]) == 0 {
            msg +>:Candidate(reasons=info.reasons):+> inc;
        }
    }
}

def cand_line(infos: list[CandInfo]) -> str {
    return ", ".join([c.inc_id + " (" + c.tier + ")" for c in infos]);
}

# ---------- Routing a rescue message (SOS / UPDATE) ----------

def route_rescue(
    hub: EkataHub,
    msg: Message,
    rep: SosReport,
    t: str,
    decs: list[Decision],
    use_ai: bool
) -> Incident {
    infos = find_candidates(hub, msg);
    ensure_candidate_edges(hub, msg, infos);
    if len(infos) == 0 {
        step(
            hub,
            decs,
            msg,
            "blocking",
            "find_candidates",
            "no open incident shares a phone, full name or place with this message",
            "NEW_INCIDENT",
            t
        );
    } else {
        step(
            hub,
            decs,
            msg,
            "blocking",
            "find_candidates",
            str(len(infos)) + " candidate incident(s): " + cand_line(infos),
            "CANDIDATES",
            t
        );
    }

    pick = Pick();
    verdict = referee_merge("", "", 0.0, 1, False);
    ref_d: Decision | None = None;
    if len(infos) > 0 {
        pick = resolve_pick(msg, infos, "", use_ai);
        step(
            hub,
            decs,
            msg,
            "resolver",
            "choose",
            pick.reason if pick.reason != "" else "no incident chosen: new incident",
            "PROPOSED" if pick.chosen != "" else "NEW_INCIDENT",
            t,
            conf=pick.score,
            model=pick.model,
            label=pick.chosen if pick.chosen != "" else msg.msg_id
        );
        tier = tier_of(infos, pick.chosen);
        verdict = referee_merge(
            pick.chosen, tier, pick.score, 1, in_candidates(infos, pick.chosen)
        );
        ref_d = step(
            hub,
            decs,
            msg,
            "referee",
            "referee_merge",
            verdict.rule + ": " + verdict.reason,
            verdict.outcome.value,
            t,
            label=pick.chosen if pick.chosen != "" else msg.msg_id
        );
        if verdict.outcome == RefereeOutcome.BLOCKED {
            blocked = find_incident(hub, pick.chosen);
            if blocked is not None {
                annotate_candidate(msg, blocked, verdict.reason);
            }
            pick = resolve_pick(msg, infos, verdict.reason, use_ai);
            step(
                hub,
                decs,
                msg,
                "resolver",
                "choose_retry",
                pick.reason
                    if pick.reason != ""
                    else "no incident chosen: new incident",
                "PROPOSED" if pick.chosen != "" else "NEW_INCIDENT",
                t,
                conf=pick.score,
                model=pick.model,
                label=pick.chosen if pick.chosen != "" else msg.msg_id
            );
            tier = tier_of(infos, pick.chosen);
            verdict = referee_merge(
                pick.chosen, tier, pick.score, 2, in_candidates(infos, pick.chosen)
            );
            ref_d = step(
                hub,
                decs,
                msg,
                "referee",
                "referee_merge_retry",
                verdict.rule + ": " + verdict.reason,
                verdict.outcome.value,
                t,
                label=pick.chosen if pick.chosen != "" else msg.msg_id
            );
        }
    }

    target: Incident | None = None;
    if verdict.outcome == RefereeOutcome.APPLIED {
        target = find_incident(hub, pick.chosen);
    }
    inc: Incident;
    if target is not None {
        inc = target;
        msg +>:PartOf(score=pick.score, reason=pick.reason):+> inc;
    } else {
        inc = new_incident(hub, rep, msg.text, t);
        msg +>:PartOf(score=1.0, reason="opened a new incident"):+> inc;
        if verdict.outcome == RefereeOutcome.NEEDS_HUMAN and pick.chosen != "" {
            prop = MergeProposal(
                msg_id=msg.msg_id,
                inc_id=pick.chosen,
                from_inc=inc.inc_id,
                score=pick.score,
                reason=pick.reason,
                storm_time=t
            );
            hub +>:Holds:+> prop;
            if ref_d is not None {
                ref_d +>:About:+> prop;
            }
        }
    }

    facts = Facts(
        kind="UPDATE" if rep.rescued else rep.kind.value,
        headcount=rep.people_count,
        vulnerable=rep.vulnerable,
        needs=rep.needs,
        place=place_display(rep),
        summary=rep.summary,
        rescued=rep.rescued
    );
    notes = apply_facts(hub, msg, inc, facts, t);
    step(
        hub,
        decs,
        msg,
        "freshness",
        "apply_facts",
        ("; ".join(notes)) if len(notes) > 0 else "no new facts to merge",
        "APPLIED",
        t,
        label=inc.inc_id
    );
    res = refresh_priority(hub, inc);
    step(
        hub,
        decs,
        msg,
        "priority",
        "score",
        f"{res.score:.0f}: {res.reason}",
        "APPLIED",
        t,
        label=inc.inc_id
    );
    return inc;
}

# ---------- Appeals and rumours ----------

def ensure_bank(hub: EkataHub, acct: str) -> BankAccount {
    for b in [hub->:Holds:->[?:BankAccount]] {
        if b.account == acct {
            return b;
        }
    }
    b = BankAccount(account=acct);
    hub +>:Holds:+> b;
    return b;
}

def ensure_url(hub: EkataHub, value: str) -> Url {
    for u in [hub->:Holds:->[?:Url]] {
        if u.value == value {
            return u;
        }
    }
    u = Url(value=value);
    hub +>:Holds:+> u;
    return u;
}

def register_appeal(
    hub: EkataHub, msg: Message, rep: SosReport, phones: list[str], t: str
) -> Appeal {
    ap = Appeal(
        appeal_id=f"APL-{msg.seq:03d}",
        text=msg.text,
        channel=msg.channel,
        source_msg_id=msg.msg_id,
        beneficiary_names=rep.claims_for_names + [p.canonical for p in rep.names],
        place_text=rep.place_text,
        credential_requests=rep.asks_credentials,
        verdict="UNVERIFIED",
        reason="",
        storm_time=t
    );
    hub +>:Holds:+> ap;
    for kind in rep.asks_credentials {
        req = CredentialRequest(kind=kind);
        hub +>:Holds:+> req;
        ap +>:Asks:+> req;
    }
    for ph in phones {
        ap +>:AppealHasPhone:+> ensure_phone(hub, ph);
    }
    for acct in rep.payee_accounts {
        ap +>:PaysTo:+> ensure_bank(hub, acct);
    }
    for u in rep.urls {
        ap +>:Links:+> ensure_url(hub, u);
    }
    if rep.claimed_office != "" {
        co = ClaimedOfficial(
            office=rep.claimed_office, contact=phones[0] if len(phones) > 0 else ""
        );
        hub +>:Holds:+> co;
        ap +>:ClaimsToBe:+> co;
    }
    log_decision(
        hub,
        "intake",
        "register_appeal",
        f"appeal {ap.appeal_id} registered for evidence review: {len(
            phones
        )} phone(s), {len(rep.payee_accounts)} account(s), {len(rep.urls)} link(s)",
        "REGISTERED",
        t,
        [msg, ap],
        confidence=rep.confidence,
        model="rules",
        target_label=ap.appeal_id
    );
    refresh_appeals(hub, ap.appeal_id);
    return ap;
}

# ---------- The pipeline ----------

def process_in_hub(
    hub: EkataHub, text: str, channel: str, storm_time: str, msg_id: str = ""
) -> Message {
    t = storm_time if storm_time != "" else hub.storm_time;
    advance_clock(hub, t);
    ch = channel.upper() if channel != "" else "WEB";
    use_ai = ai_enabled();
    decs: list[Decision] = [];

    out = run_intake(text, ch);
    rep = out.rep;
    mid = msg_id if msg_id != "" else next_msg_id(hub);
    msg = Message(
        msg_id=mid,
        text=text,
        channel=ch,
        language=rep.language,
        storm_time=t,
        kind=rep.kind.value,
        seq=next_message_seq(hub)
    );
    hub +>:Holds:+> msg;
    phones = attach_identifiers(hub, msg, rep);
    why = f"read as {rep.kind.value}: {len(phones)} phone(s), {len(rep.names)} name(s)";
    if rep.people_count > 0 {
        why = why + f", {rep.people_count} people";
    }
    if rep.place_text != "" {
        why = why + ", place " + rep.place_text;
    }
    if out.note != "" {
        why = why + ". " + out.note;
    }
    step(
        hub,
        decs,
        msg,
        "intake",
        "extract",
        why,
        "APPLIED",
        t,
        conf=rep.confidence,
        model=out.model
    );

    inc: Incident | None = None;
    if rep.kind == MsgKind.SOS or rep.kind == MsgKind.UPDATE {
        inc = route_rescue(hub, msg, rep, t, decs, use_ai);
    } elif rep.kind == MsgKind.APPEAL {
        register_appeal(hub, msg, rep, phones, t);
    } elif rep.kind == MsgKind.RUMOUR {
        claim = RumourClaim(
            claim=text, source_msg_id=msg.msg_id,
            stance="UNCONFIRMED",
            storm_time=t
        );
        hub +>:Holds:+> claim;
        link_bulletins(hub, claim);
        log_decision(
            hub,
            "intake",
            "register_rumour",
            "unverified claim recorded as UNCONFIRMED; never enters the call queue (R7)",
            "UNCONFIRMED",
            t,
            [msg, claim],
            confidence=rep.confidence,
            model=out.model,
            target_label=msg.msg_id
        );
    } else {
        step(
            hub,
            decs,
            msg,
            "intake",
            "note_offer",
            "an offer of help is recorded; it is not a call-queue item (R7)",
            "APPLIED",
            t,
            model=out.model
        );
    }
    refresh_appeals(hub);
    for rumour in [hub ->:Holds:->[?:RumourClaim]] { link_bulletins(hub, rumour); }
    if inc is not None {
        for d in decs {
            d +>:About:+> inc;
        }
    }
    return msg;
}

# Public entry: one message through the pipeline on the shared hub, one commit.
def process_message(
    text: str, channel: str, storm_time: str, msg_id: str = ""
) -> Message {
    hub = get_hub();
    ensure_seeded(hub);
    msg = process_in_hub(hub, text, channel, storm_time, msg_id);
    commit();
    return msg;
}

# ---------- Views ----------

def msg_view(m: Message) -> MsgView {
    return MsgView(
        msg_id=m.msg_id,
        text=m.text,
        channel=m.channel,
        storm_time=m.storm_time,
        kind=m.kind,
        language=m.language
    );
}

def trace_row(d: Decision) -> TraceRow {
    return TraceRow(
        seq=d.seq,
        agent=d.agent,
        action=d.action,
        reason=d.reason,
        outcome=d.outcome,
        storm_time=d.storm_time,
        target=d.target,
        confidence=d.confidence, model=d.model
    );
}

def decisions_since(hub: EkataHub, cursor: int, limit: int) -> list[TraceRow] {
    ds = sorted(
        [hub->:Holds:->[?:Decision, seq>cursor]], key=lambda (d: Decision) { d.seq; }
    );
    rows: list[TraceRow] = [];
    for d in ds[:limit] {
        rows.append(trace_row(d));
    }
    return rows;
}

def build_queue(hub: EkataHub) -> list[QueueRow] {
    rows: list[QueueRow] = [];
    for inc in all_incidents(hub) {
        if inc.status not in OPEN_STATUSES {
            continue;
        }
        res = priority_now(hub, inc);
        rows.append(
            QueueRow(
                inc_id=inc.inc_id,
                priority=res.score,
                status=inc.status,
                headline=inc.summary if inc.summary != "" else inc.place,
                place=inc.place,
                headcount=inc.headcount,
                vulnerable=inc.vulnerable,
                msg_count=len(messages_of(inc)),
                reason=res.reason,
                waiting=fmt_minutes(storm_diff(hub.storm_time, inc.first_seen))
            )
        );
    }
    rows = sorted(rows, key=lambda (r: QueueRow) { (-r.priority, r.inc_id); });
    for (i, r) in enumerate(rows) {
        r.rank = i + 1;
    }
    return overlay_rank(hub, rows);
}

def build_incident_view(hub: EkataHub, inc: Incident) -> IncidentView {
    msgs = messages_of(inc);
    ids = [m.msg_id for m in msgs];
    cands: list[CandidateView] = [];
    seen: list[str] = [];
    for m in msgs {
        for ci in [m->:Candidate:->[?:Incident]] {
            if ci.inc_id in seen {
                continue;
            }
            seen.append(ci.inc_id);
            reasons: list[str] = [];
            for e in [edge m->:Candidate:->ci] {
                reasons = reasons + e.reasons;
            }
            cands.append(CandidateView(inc_id=ci.inc_id, reasons=reasons));
        }
    }
    props: list[ProposalView] = [];
    for p in all_proposals(hub) {
        if p.inc_id == inc.inc_id or p.from_inc == inc.inc_id or p.msg_id in ids {
            props.append(
                ProposalView(
                    msg_id=p.msg_id,
                    inc_id=p.inc_id,
                    score=p.score,
                    reason=p.reason,
                    outcome="NEEDS_HUMAN" if p.status == "PENDING" else p.status
                )
            );
        }
    }
    calls: list[CallView] = [];
    logs = sorted(
        [inc<-:Logged:<-[?:CallLog]],
        key=lambda (c: CallLog) { storm_minutes(c.storm_time); }
    );
    for c in logs {
        calls.append(
            CallView(
                outcome=c.outcome, desk=c.desk, storm_time=c.storm_time, note=c.note
            )
        );
    }
    trace: list[TraceRow] = [];
    for d in sorted(
        [inc<-:About:<-[?:Decision]], key=lambda (d: Decision) { d.seq; }
    ) {
        trace.append(trace_row(d));
    }
    return IncidentView(
        inc_id=inc.inc_id,
        status=inc.status,
        priority=priority_now(hub, inc).score,
        headcount=inc.headcount,
        place=inc.place,
        needs=inc.needs,
        vulnerable=inc.vulnerable,
        summary=inc.summary,
        claimed_by=inc.claimed_by,
        messages=[msg_view(m) for m in msgs],
        pending=[ChangeView(field=p.fld, old_value=p.old_value, new_value=p.new_value, msg_id=p.msg_id) for p in open_pending(hub, inc.inc_id)],
        candidates=cands,
        proposals=props,
        calls=calls,
        trace=trace
    );
}

# ---------- Desk decisions ----------

# Approve or reject a pending merge. Returns the incident the message now sits in.
def apply_merge_decision(
    hub: EkataHub, msg_id: str, inc_id: str, approve: bool, desk: str
) -> Incident | None {
    msg = find_message(hub, msg_id);
    target = find_incident(hub, inc_id);
    if msg is None or target is None {
        return None;
    }
    prop: MergeProposal | None = None;
    for p in all_proposals(hub) {
        if p.msg_id == msg_id and p.inc_id == inc_id and p.status == "PENDING" {
            prop = p;
            break;
        }
    }
    old = incident_of(msg);
    if prop is None {
        return old;
    }
    t = hub.storm_time;
    if not approve {
        prop.status = "REJECTED";
        prop.decided_by = desk;
        log_decision(
            hub,
            "desk",
            "merge_rejected",
            f"{desk} kept {msg_id} apart from {inc_id}: the separate incident stays",
            "REJECTED",
            t,
            [msg, target, prop],
            confidence=1.0,
            model="human",
            target_label=inc_id
        );
        return old;
    }
    prop.status = "APPROVED";
    prop.decided_by = desk;
    if old is not None and old.inc_id != target.inc_id {
        facts = Facts(
            kind=msg.kind,
            headcount=old.headcount,
            vulnerable=old.vulnerable,
            needs=old.needs,
            place=old.place,
            summary=old.summary,
            rescued=False
        );
        del [edge msg->:PartOf:->old];
        msg +>:PartOf(score=prop.score, reason=prop.reason, approved_by=desk):+> target;
        apply_facts(hub, msg, target, facts, msg.storm_time);
        if len(messages_of(old)) == 0 {
            for d in [old<-:About:<-[?:Decision]] {
                d +>:About:+> target;
            }
            del old;
        }
    }
    log_decision(
        hub,
        "desk",
        "merge_approved",
        f"{desk} approved merging {msg_id} into {inc_id}",
        "APPLIED",
        t,
        [msg, target, prop],
        confidence=1.0,
        model="human",
        target_label=inc_id
    );
    res = refresh_priority(hub, target);
    log_decision(
        hub,
        "priority",
        "score",
        f"{res.score:.0f}: {res.reason}",
        "APPLIED",
        t,
        [target],
        confidence=1.0,
        model="rules",
        target_label=inc_id
    );
    return incident_of(msg);
}

glob CALL_OUTCOMES: dict[str, str] = {
         "REACHED_CONFIRMED": "CONFIRMED",
         "NO_ANSWER": "",
         "RESCUED": "RESOLVED",
         "STILL_IN_NEED": "VERIFYING"
     };

# Log a call attempt, apply R5 (one desk per incident) and R4 (status needs a call).
def record_call(
    hub: EkataHub, inc_id: str, outcome: str, desk: str, note: str
) -> Incident | None {
    inc = find_incident(hub, inc_id);
    if inc is None {
        return None;
    }
    t = hub.storm_time;
    if outcome not in CALL_OUTCOMES {
        log_decision(
            hub,
            "referee",
            "call_rejected",
            "unknown call outcome " + outcome,
            "BLOCKED",
            t,
            [inc],
            confidence=1.0,
            model="rules",
            target_label=inc_id
        );
        return inc;
    }
    claim = r5_claim(inc.claimed_by, desk);
    if claim.outcome == RefereeOutcome.BLOCKED {
        log_decision(
            hub,
            "referee",
            "claim_blocked",
            claim.rule + ": " + claim.reason,
            "BLOCKED",
            t,
            [inc],
            confidence=1.0,
            model="rules",
            target_label=inc_id
        );
        return inc;
    }
    inc.claimed_by = desk;
    call = CallLog(outcome=outcome, desk=desk, storm_time=t, note=note);
    hub +>:Holds:+> call;
    call +>:Logged:+> inc;
    log_decision(
        hub,
        "desk",
        "call_logged",
        f"{desk} called: {outcome}" + ((" - " + note) if note != "" else ""),
        "APPLIED",
        t,
        [inc, call],
        confidence=1.0,
        model="human",
        target_label=inc_id
    );
    new_status = CALL_OUTCOMES[outcome];
    if new_status != "" {
        v = change_status(inc, new_status);
        log_decision(
            hub,
            "referee",
            "status_change",
            v.rule + ": " + v.reason + f" ({inc.status})",
            v.outcome.value,
            t,
            [inc],
            confidence=1.0,
            model="rules",
            target_label=inc_id
        );
    }
    if outcome == "RESCUED" or outcome == "NO_ANSWER" {
        inc.claimed_by = "";
        if outcome == "NO_ANSWER" and inc.status == "VERIFYING" { inc.status = "NEW"; }
    }
    res = refresh_priority(hub, inc);
    log_decision(
        hub,
        "priority",
        "score",
        f"{res.score:.0f}: {res.reason}",
        "APPLIED",
        t,
        [inc],
        confidence=1.0,
        model="rules",
        target_label=inc_id
    );
    refresh_appeals(hub);
    return inc;
}

# ---------- Replay ----------

def replay_in_hub(hub: EkataHub, steps: int) -> ReplayStep {
    ensure_seeded(hub);
    before = hub.decision_seq;
    if hub.replay_lock {
        return ReplayStep(
            locked=True,
            position=hub.replay_pos,
            total=hub.replay_total,
            storm_time=hub.storm_time,
            queue=build_queue(hub)
        );
    }
    hub.replay_lock = True;
    commit();
    last: Message | None = None;
    n = steps;
    if n < 1 {
        n = 1;
    }
    if n > 25 {
        n = 25;
    }
    try {
        for i in range(n) {
            fm = peek_next(hub);
            if fm is None {
                break;
            }
            try {
                last = process_in_hub(
                    hub, fm.text, fm.channel, fm.storm_time, fm.msg_id
                );
            } except Exception as e {
                log_decision(
                    hub,
                    "intake",
                    "error",
                    "processing " + fm.msg_id + " failed: " + str(e)[:120],
                    "FAILED",
                    fm.storm_time,
                    [],
                    confidence=0.0,
                    model="rules",
                    target_label=fm.msg_id
                );
            }
            hub.replay_pos += 1;
            commit();
        }
    } finally {
        hub.replay_lock = False;
        commit();
    }
    return ReplayStep(
        done=hub.replay_total > 0 and hub.replay_pos >= hub.replay_total,
        locked=False,
        position=hub.replay_pos,
        total=hub.replay_total,
        storm_time=hub.storm_time,
        message=msg_view(last) if last is not None else None,
        queue=build_queue(hub),
        new_trace=decisions_since(hub, before, 400)
    );
}

# ---------- Metrics ----------

def build_metrics(hub: EkataHub) -> Metrics {
    msgs = all_messages(hub);
    rescue = len(
        [
            m
            for m in msgs
            if m.kind == "SOS" or m.kind == "UPDATE"
        ]
    );
    incs = all_incidents(hub);
    open_n = len(
        [
            i
            for i in incs
            if i.status in OPEN_STATUSES
        ]
    );
    saved = rescue - len(incs);
    if saved < 0 {
        saved = 0;
    }
    return Metrics(
        messages=len(msgs),
        rescue_messages=rescue,
        incidents=len(incs),
        calls_needed=open_n,
        calls_saved=saved,
        note="eval pending"
    );
}
