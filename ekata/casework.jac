"""Evidence-led appeal review and rumour routing. Model tools are read-only."""
import os;
import from ekata.replay_cache { read_cached, record_cached }
import re;
import from ekata.schema {
    EkataHub, Holds, Appeal, PersonName, Phone, BankAccount, Url, ClaimedOfficial, RegistryEntry,
    Incident, Message, RumourClaim, Bulletin, Decision, Candidate, ClaimsFor,
    AppealHasPhone, PaysTo, Links, ClaimsToBe, ListedAs, Checks, HasPhone, Names, At,
    CallLog, Logged, ResourceRequest, RequestFor, GNDivision, DSDivision, LocatedIn, InDS
}
import from ekata.store { all_incidents, messages_of, has_call_log, normalise_phone, normalise_name, normalise_place, place_compatible, log_decision, storm_minutes }
import from ekata.ai.models { strong, budget_hook, drain_agent_steps, last_model }

glob investigator_model: any = strong;

node CredentialRequest { has kind: str; }
edge Asks: Appeal --> CredentialRequest {}
node CaseFile {
    has appeal_id: str;
    has summary: str = "";
    has approved_by: str = "";
    has warning_draft: str = "";
    has native_reviewed: bool = False;
}
edge Describes: CaseFile --> Appeal {}

obj Evidence {
    has ref: str;
    has kind: str;
    has text: str;
}
obj Investigation {
    has reason: str = "";
    has confidence: float = 0.0;
    has evidence_ids: list[str] = [];
}
sem Investigation = "A cited explanation of the available evidence, never an unsupported scam accusation.";
sem Investigation.evidence_ids = "Only reference IDs returned by the read-only tools; never invent IDs.";

obj AppealView {
    has appeal_id: str;
    has text: str;
    has verdict: str = "UNVERIFIED";
    has reason: str = "";
    has evidence: list[Evidence] = [];
    has incident_ids: list[str] = [];
    has approved_by: str = "";
    has storm_time: str = "";
    has model: str = "rules";
    has case_summary: str = "";
    has warning_draft: str = "";
}
obj RumourView {
    has claim: str;
    has source_id: str = "";
    has stance: str = "UNCONFIRMED";
    has bulletins: list[Evidence] = [];
    has storm_time: str = "";
}

def find_appeal(hub: EkataHub, appeal_id: str) -> Appeal | None {
    for ap in [hub ->:Holds:->[?:Appeal]] {
        if ap.appeal_id == appeal_id { return ap; }
    }
    return None;
}

def shared_appeals(ap: Appeal) -> list[Appeal] {
    out: list[Appeal] = [];
    seen: list[str] = [];
    for b in [ap ->:PaysTo:->[?:BankAccount]] {
        for other in [b <-:PaysTo:<-[?:Appeal]] {
            if other.appeal_id != ap.appeal_id and other.appeal_id not in seen {
                out.append(other); seen.append(other.appeal_id);
            }
        }
    }
    for ph in [ap ->:AppealHasPhone:->[?:Phone]] {
        for other in [ph <-:AppealHasPhone:<-[?:Appeal]] {
            if other.appeal_id != ap.appeal_id and other.appeal_id not in seen {
                out.append(other); seen.append(other.appeal_id);
            }
        }
    }
    for u in [ap ->:Links:->[?:Url]] {
        for other in [u <-:Links:<-[?:Appeal]] {
            if other.appeal_id != ap.appeal_id and other.appeal_id not in seen {
                out.append(other); seen.append(other.appeal_id);
            }
        }
    }
    return out;
}

# A call verifies a household only when it reached someone.
glob VERIFYING_CALLS: list[str] = ["REACHED_CONFIRMED", "STILL_IN_NEED", "RESCUED"];

def verifying_call_of(inc: Incident) -> CallLog | None {
    best: CallLog | None = None;
    for c in [inc <-:Logged:<-[?:CallLog]] {
        if c.outcome in VERIFYING_CALLS and (best is None or c.storm_time >= best.storm_time) { best = c; }
    }
    return best;
}

# Households the appeal names (same phone, or same person at a compatible place).
def named_households(hub: EkataHub, ap: Appeal) -> list[Incident] {
    phones = [p.number for p in [ap ->:AppealHasPhone:->[?:Phone]]];
    out: list[Incident] = [];
    for inc in all_incidents(hub) {
        matched = False;
        for m in messages_of(inc) {
            for ph in [m ->:HasPhone:->[?:Phone]] {
                if ph.number in phones { matched = True; }
            }
            for person in [m ->:Names:->[?:PersonName]] {
                if person.canonical in ap.beneficiary_names and ap.place_text != "" and place_compatible(normalise_place(ap.place_text), normalise_place(inc.place)) { matched = True; }
            }
        }
        if matched { out.append(inc); }
    }
    return out;
}

def verified_matches(hub: EkataHub, ap: Appeal) -> list[Incident] {
    return [inc for inc in named_households(hub, ap) if inc.status in ["CONFIRMED", "VERIFYING", "RESOLVED"] and verifying_call_of(inc) is not None];
}

# The verified household record, reused as appeal evidence.
def household_record(inc: Incident) -> str {
    call = verifying_call_of(inc);
    ds = "";
    for gn in [inc ->:LocatedIn:->[?:GNDivision]] {
        for d in [gn ->:InDS:->[?:DSDivision]] { ds = d.name; }
    }
    who = f"{inc.headcount} people" if inc.headcount > 0 else "headcount not given";
    text = f"Verified by phone ({call.desk} at {call.storm_time}): {who}" if call is not None else f"Not yet verified: {who}";
    if ds != "" { text = text + f" in {ds} division"; }
    helping = [r for r in [inc <-:RequestFor:<-[?:ResourceRequest]] if r.status in ["ACCEPTED", "DISPATCHED", "DELIVERED"]];
    if len(helping) > 0 {
        text = text + ". Relief is coordinated through " + ", ".join([f"{r.ngo} ({r.need}, {r.status.lower()})" for r in helping]);
    } else {
        text = text + ". No relief group is assigned yet";
    }
    return text + ".";
}

obj AppealFacts {
    has evidence: list[Evidence] = [];
    has signals: list[str] = [];
    has matches: list[Incident] = [];
    has official: bool = False;
}

def collect_facts(hub: EkataHub, ap: Appeal) -> AppealFacts {
    facts = AppealFacts(matches=verified_matches(hub, ap));
    related = shared_appeals(ap);
    ring = False;
    for b in [ap ->:PaysTo:->[?:BankAccount]] { if len([b <-:PaysTo:<-[?:Appeal]]) >= 3 { ring = True; } }
    for p in [ap ->:AppealHasPhone:->[?:Phone]] { if len([p <-:AppealHasPhone:<-[?:Appeal]]) >= 3 { ring = True; } }
    for u in [ap ->:Links:->[?:Url]] { if len([u <-:Links:<-[?:Appeal]]) >= 3 { ring = True; } }
    if ring {
        facts.signals.append("shared_identifier_ring");
        for other in related { facts.evidence.append(Evidence(ref=other.appeal_id, kind="shared_identifier", text=other.text)); }
    }
    phones = [p.number for p in [ap ->:AppealHasPhone:->[?:Phone]]];
    for co in [ap ->:ClaimsToBe:->[?:ClaimedOfficial]] {
        registered = False;
        for reg in [hub ->:Holds:->[?:RegistryEntry]] {
            if normalise_name(co.office) == normalise_name(reg.office) {
                registered = True;
                contact_ok = normalise_phone(reg.contact) in phones;
                if contact_ok { facts.official = True; }
                else { facts.signals.append("official_contact_mismatch"); }
                facts.evidence.append(Evidence(ref="registry:" + reg.office, kind="registry", text=reg.office + ": " + reg.contact + (" (contact matches)" if contact_ok else " (contact does not match)")));
            }
        }
        if not registered {
            facts.signals.append("unregistered_claimed_office");
            facts.evidence.append(Evidence(ref="office:" + co.office, kind="impersonation", text="Claimed office is absent from the synthetic registry: " + co.office));
        }
    }
    # A registered NGO's exact contact is an official channel even without an office claim.
    for reg in [hub ->:Holds:->[?:RegistryEntry]] {
        if reg.kind == "NGO" and normalise_phone(reg.contact) in phones {
            facts.official = True;
            facts.evidence.append(Evidence(ref="registry:" + reg.office, kind="registry", text="Registered NGO contact matches " + reg.office));
        }
    }
    if len(ap.credential_requests) > 0 {
        facts.signals.append("requests_reader_credentials");
        facts.evidence.append(Evidence(ref=ap.source_msg_id, kind="credential_request", text="Requests from the reader: " + ", ".join(ap.credential_requests)));
    }
    for inc in facts.matches {
        facts.evidence.append(Evidence(ref=inc.inc_id, kind="verified_incident", text=household_record(inc)));
    }
    for inc in named_households(hub, ap) {
        if inc not in facts.matches {
            facts.evidence.append(Evidence(ref=inc.inc_id, kind="unverified_household", text="The appeal names this household, but no officer has reached it yet. Wait for verification before donating."));
        }
    }
    facts.signals = list(set(facts.signals));
    return facts;
}

# R8-R9. Repeated identifiers alone are one signal, not independent proof.
def referee_appeal(signals: list[str], confirmed: bool, official: bool) -> str {
    categories = set(["claimed_office" if x in ["official_contact_mismatch", "unregistered_claimed_office"] else x for x in signals]);
    if len(categories) >= 2 { return "LIKELY_SCAM"; }
    if len(categories) == 1 { return "SUSPICIOUS"; }
    if confirmed and official { return "MATCHED"; }
    return "UNVERIFIED";
}

# R10-R11: no public warning without approval; Sinhala/Tamil also need native review.
def warning_allowed(approved: bool, language: str, native_reviewed: bool) -> bool {
    return approved and (language not in ["si", "ta"] or native_reviewed);
}

obj AnalystTools {
    has hub: EkataHub;
    has appeal_id: str;

    def lookup_official() -> list[Evidence] {
        ap = find_appeal(self.hub, self.appeal_id);
        if ap is None { return []; }
        return [e for e in collect_facts(self.hub, ap).evidence if e.kind == "registry" or e.kind == "impersonation"];
    }
    def appeals_sharing() -> list[Evidence] {
        ap = find_appeal(self.hub, self.appeal_id);
        if ap is None { return []; }
        return [Evidence(ref=x.appeal_id, kind="shared_identifier", text=x.text) for x in shared_appeals(ap)];
    }
    def verified_incident_for() -> list[Evidence] {
        ap = find_appeal(self.hub, self.appeal_id);
        if ap is None { return []; }
        return [Evidence(ref=x.inc_id, kind="verified_incident", text=x.summary) for x in verified_matches(self.hub, ap)];
    }
    def investigate(text: str) -> Investigation by investigator_model(
        tools=[self.lookup_official, self.appeals_sharing, self.verified_incident_for],
        max_react_iterations=4, on_iteration=budget_hook, temperature=0.0,
        incl_info={"policy": "Use the read-only tools and cite returned reference IDs. Not verified yet is never fraud. Reused account/phone/URL is one signal; an accusation requires an independent fraud signal. Explain uncertainties. Never publish a warning."}
    );
}
sem AnalystTools.lookup_official = "Check the claimed office and official contact against the fictional registry.";
sem AnalystTools.appeals_sharing = "Find other appeals connected by a shared payee, phone or URL.";
sem AnalystTools.verified_incident_for = "Find only confirmed incidents supported by a human call log.";

walker AppealExplorer {
    has visited: list[str] = [];
    can begin with Appeal entry {
        visit [->:PaysTo:->] by investigator_model(select=1, intent="Follow the payee account lead relevant to verifying this appeal");
    }
    can account with BankAccount entry { self.visited.append(here.account); }
}

def review_appeal(hub: EkataHub, ap: Appeal, use_ai: bool = False) -> AppealView {
    facts = collect_facts(hub, ap);
    verdict = referee_appeal(facts.signals, len(facts.matches) > 0, facts.official);
    explanation = "No verified incident and official channel yet; this alone is not evidence of fraud.";
    if verdict == "MATCHED" { explanation = "Matches a household an officer verified by phone, and the contact is a registered channel. " + household_record(facts.matches[0]); }
    if len(facts.signals) > 0 { explanation = "; ".join(facts.signals) + ". Analyst review required."; }
    if not use_ai and ap.verdict == verdict and ap.reason != "" { explanation = ap.reason; }
    if use_ai {
        try {
            payload: dict[str, any] = {"text": ap.text, "evidence": [e.ref + ":" + e.text for e in facts.evidence], "signals": sorted(facts.signals)};
            cached: any = read_cached("appeal", payload);
            result = Investigation();
            if cached is not None {
                value: any = cached["value"];
                result = Investigation(reason=str(value["reason"]), confidence=float(value["confidence"]), evidence_ids=[str(x) for x in value["evidence_ids"]]);
                ap.model = "cached:" + str(cached["model"]);
            } else {
                ap spawn AppealExplorer();
                result = AnalystTools(hub=hub, appeal_id=ap.appeal_id).investigate(ap.text);
                ap.model = last_model() or "configured model pool";
                record_cached("appeal", payload, {"reason": result.reason, "confidence": result.confidence, "evidence_ids": result.evidence_ids}, ap.model);
            }
            known = [e.ref for e in facts.evidence];
            cited = [ref for ref in result.evidence_ids if ref in known];
            if len(cited) > 0 and result.reason != "" { explanation = result.reason + " [" + ", ".join(cited) + "]"; }
        } except Exception { ap.model = "rules"; }
        for row in drain_agent_steps() {
            log_decision(hub, "appeal_investigator", "tool_call", str(row.get("tool", "tool")) + ": " + str(row.get("result_preview", "")), "READ_ONLY", hub.storm_time, [ap], model=ap.model, target_label=ap.appeal_id);
        }
    }
    if ap.verdict != verdict { ap.approved_by = ""; }
    ap.verdict = verdict;
    ap.reason = explanation;
    for inc in facts.matches {
        if len([edge ap ->:ClaimsFor:-> inc]) == 0 { ap +>:ClaimsFor(match_score=1.0):+> inc; }
    }
    return AppealView(appeal_id=ap.appeal_id, text=ap.text, verdict=verdict, reason=explanation, evidence=facts.evidence, incident_ids=[x.inc_id for x in facts.matches], approved_by=ap.approved_by, storm_time=ap.storm_time, model=ap.model);
}

def refresh_appeals(hub: EkataHub, newest: str = "") {
    for ap in [hub ->:Holds:->[?:Appeal]] {
        old = ap.verdict;
        view = review_appeal(hub, ap, ap.appeal_id == newest and os.environ.get("EKATA_AI", "on") != "off");
        if old != ap.verdict {
            log_decision(hub, "appeal_referee", "verdict", view.reason, view.verdict, hub.storm_time, [ap], model=ap.model, target_label=ap.appeal_id);
        }
    }
}


def appeal_view(hub: EkataHub, ap: Appeal) -> AppealView {
    facts = collect_facts(hub, ap);
    view = AppealView(appeal_id=ap.appeal_id, text=ap.text, verdict=ap.verdict, reason=ap.reason, evidence=facts.evidence, incident_ids=[x.inc_id for x in facts.matches], approved_by=ap.approved_by, storm_time=ap.storm_time, model=ap.model);
    for c in [ap <-:Describes:<-[?:CaseFile]] {
        view.case_summary = c.summary; view.warning_draft = c.warning_draft;
    }
    return view;
}

def link_bulletins(hub: EkataHub, claim: RumourClaim) {
    for b in [hub ->:Holds:->[?:Bulletin]] {
        if storm_minutes(b.issued_at) > storm_minutes(hub.storm_time) { continue; }
        if b.area.lower() in claim.claim.lower() {
            stance = "COMPARE_WITH_BULLETIN";
            if "kotmale" in claim.claim.lower() and "breach" in claim.claim.lower() and "safe" in b.text.lower() { stance = "CONTRADICTED_BY_BULLETIN"; }
            claim +>:Checks(stance=stance):+> b;
            claim.stance = stance;
        }
    }
}

def rumour_view(hub: EkataHub, claim: RumourClaim) -> RumourView {
    notices: list[Evidence] = [];
    low = claim.claim.lower();
    for b in [hub ->:Holds:->[?:Bulletin]] {
        if storm_minutes(b.issued_at) > storm_minutes(hub.storm_time) { continue; }
        if b.area.lower() in low or ("kotmale" in low and "kotmale" in b.area.lower()) {
            notices.append(Evidence(ref="bulletin:" + b.issuer + ":" + b.area + ":" + b.issued_at, kind="official_bulletin", text=b.text + " (issued " + b.issued_at + ")"));
        }
    }
    return RumourView(claim=claim.claim, source_id=claim.source_msg_id, stance=claim.stance, bulletins=notices, storm_time=claim.storm_time);
}
