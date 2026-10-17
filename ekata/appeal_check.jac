"""Appeal checking (R8/R9): fraud signals, then a verdict. Pure reads; only
check_all_appeals(apply=True) writes, and the caller is the single writer.

Official-channel idea (Japan after 2011): donate only through channels in the
registry. "No verified incident yet" is never evidence of fraud.
"""

import re;
import from ekata.schema {
    EkataHub, Holds, Message, Incident, Appeal, Phone, PersonName, BankAccount, Url,
    ClaimedOfficial, RegistryEntry, PaysTo, AppealHasPhone, Links, ClaimsToBe, Names, PartOf
}
import from ekata.store { normalise_phone, normalise_name, is_full_name }

obj AppealVerdict {
    has appeal_id: str;
    has verdict: str;
    has signals: list[str];
    has evidence: list[str];
    has reason: str;
}

glob RING_SIZE: int = 3;
glob CRED_PATTERN: str = r"\b(nic|otp|one[\s\-]?time\s+(?:code|password|pin)|bank\s+login|net\s*banking|password|passcode|card\s+number|cvv)\b";

def appeal_ids(aps: list[Appeal]) -> str {
    ids = sorted([a.appeal_id for a in aps]);
    return ", ".join(ids);
}

def ring_signals(ap: Appeal) -> list[str] {
    ev: list[str] = [];
    for acct in [ap ->:PaysTo:->[?:BankAccount]] {
        group = [acct <-:PaysTo:<-[?:Appeal]];
        if len(group) >= RING_SIZE {
            ev.append(f"account {acct.account} shared by {len(group)} appeals: {appeal_ids(group)}");
        }
    }
    for ph in [ap ->:AppealHasPhone:->[?:Phone]] {
        group = [ph <-:AppealHasPhone:<-[?:Appeal]];
        if len(group) >= RING_SIZE {
            ev.append(f"phone {ph.number} shared by {len(group)} appeals: {appeal_ids(group)}");
        }
    }
    for u in [ap ->:Links:->[?:Url]] {
        group = [u <-:Links:<-[?:Appeal]];
        if len(group) >= RING_SIZE {
            ev.append(f"link {u.value} shared by {len(group)} appeals: {appeal_ids(group)}");
        }
    }
    return ev;
}

def office_matches(a: str, b: str) -> bool {
    x = a.strip().lower();
    y = b.strip().lower();
    if x == "" or y == "" {
        return False;
    }
    return x in y or y in x;
}

def registry_of(hub: EkataHub) -> list[RegistryEntry] {
    return [hub ->:Holds:->[?:RegistryEntry]];
}

# Returns (impersonation evidence, whether a claimed office is a registered one).
def impersonation_check(hub: EkataHub, ap: Appeal) -> tuple[list[str], bool] {
    ev: list[str] = [];
    listed = False;
    reg = registry_of(hub);
    for co in [ap ->:ClaimsToBe:->[?:ClaimedOfficial]] {
        hits = [r for r in reg if office_matches(co.office, r.office)];
        if len(hits) == 0 {
            ev.append(f"claimed office '{co.office}' is not in the official registry");
            continue;
        }
        claimed = normalise_phone(co.contact);
        ok = False;
        for r in hits {
            if claimed != "" and claimed == normalise_phone(r.contact) {
                ok = True;
            }
        }
        if ok {
            listed = True;
        } else {
            ev.append(
                f"claimed office '{co.office}' is registered with contact {hits[0].contact}, but the appeal gives '{co.contact}'"
            );
        }
    }
    return (ev, listed);
}

def credential_evidence(text: str) -> list[str] {
    ev: list[str] = [];
    found: list[str] = [];
    for m in re.finditer(CRED_PATTERN, text, re.IGNORECASE) {
        w = m.group(0).lower();
        if w not in found {
            found.append(w);
        }
    }
    if len(found) > 0 {
        ev.append("text asks the reader for: " + ", ".join(found));
    }
    return ev;
}

# Canonical full names of people in CONFIRMED incidents.
def confirmed_names(hub: EkataHub) -> dict[str, str] {
    out: dict[str, str] = {};
    for inc in [hub ->:Holds:->[?:Incident, status == "CONFIRMED"]] {
        for m in [inc <-:PartOf:<-[?:Message]] {
            for pn in [m ->:Names:->[?:PersonName]] {
                if is_full_name(pn.canonical) {
                    out[pn.canonical] = inc.inc_id;
                }
            }
        }
    }
    return out;
}

def named_confirmed(hub: EkataHub, text: str) -> list[str] {
    padded = " " + normalise_name(text) + " ";
    hits: list[str] = [];
    cn = confirmed_names(hub);
    for canon in cn.keys() {
        if (" " + canon + " ") in padded {
            hits.append(f"names {canon} of confirmed incident {cn[canon]}");
        }
    }
    return hits;
}

def text_names_registered_office(hub: EkataHub, ap: Appeal) -> bool {
    low = ap.text.lower();
    for r in registry_of(hub) {
        if r.office.strip() != "" and r.office.strip().lower() in low {
            return True;
        }
    }
    return False;
}

def check_appeal(hub: EkataHub, ap: Appeal) -> AppealVerdict {
    signals: list[str] = [];
    evidence: list[str] = [];

    ring = ring_signals(ap);
    if len(ring) > 0 {
        signals.append("RING");
        evidence.extend(ring);
    }
    imp = impersonation_check(hub, ap);
    if len(imp[0]) > 0 {
        signals.append("IMPERSONATION");
        evidence.extend(imp[0]);
    }
    cred = credential_evidence(ap.text);
    if len(cred) > 0 {
        signals.append("CREDENTIALS");
        evidence.extend(cred);
    }

    verdict = "UNVERIFIED";
    reason = "";
    if len(signals) >= 2 {
        verdict = "LIKELY_SCAM";
        reason = f"{len(signals)} independent fraud signals: " + ", ".join(signals);
    } elif len(signals) == 1 {
        verdict = "SUSPICIOUS";
        reason = "one fraud signal: " + signals[0];
    } else {
        names = named_confirmed(hub, ap.text);
        official = imp[1] or text_names_registered_office(hub, ap);
        if len(names) > 0 and official {
            verdict = "MATCHED";
            evidence.extend(names);
            evidence.append("appeal comes through a registered official channel");
            reason = "no fraud signal; names a person in a confirmed incident via an official channel";
        } else {
            reason = "no fraud signal, but no confirmed incident and official channel match yet (not evidence of fraud)";
        }
    }
    return AppealVerdict(
        appeal_id=ap.appeal_id, verdict=verdict, signals=signals, evidence=evidence, reason=reason
    );
}

def verdict_rank(v: str) -> int {
    order = ["LIKELY_SCAM", "SUSPICIOUS", "UNVERIFIED", "MATCHED"];
    if v in order {
        return order.index(v);
    }
    return len(order);
}

def check_all_appeals(hub: EkataHub, apply: bool) -> list[AppealVerdict] {
    out: list[AppealVerdict] = [];
    for ap in [hub ->:Holds:->[?:Appeal]] {
        v = check_appeal(hub, ap);
        if apply {
            ap.verdict = v.verdict;
            ap.reason = v.reason;
        }
        out.append(v);
    }
    return sorted(out, key=lambda (v: AppealVerdict) { (verdict_rank(v.verdict), v.appeal_id); });
}
