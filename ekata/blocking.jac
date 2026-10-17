"""Blocking rules (A3a): plain Jac, no LLM.

A Blocker walker starts on the new Message, hops to its identifier nodes
(Phone, PersonName, Place), and from each one looks back at the other
messages that share it and the incidents those messages belong to. The
result is written as Candidate edges (Message -> Incident) carrying the
reasons; those edges are what the Resolver chooses among.

Evidence tiers (R1):
  STRONG  exact phone, or full name + the same household-level place
  MEDIUM  full name alone, or a household-level place alone
  WEAK    same surname on the same road or village
A surname alone, or a road- or village-level place alone, is never evidence
by itself: it only counts together with the other (WEAK at best).
"""

import from ekata.schema {
    EkataHub, Message, Incident, Phone, PersonName, Place,
    HasPhone, Names, At, PartOf, Candidate
}
import from ekata.store {
    find_incident, is_full_name, surname_of, phone_display, title_case,
    household_display, to_int
}

obj CandInfo {
    has inc_id: str;
    has tier: str = "WEAK";
    has reasons: list[str] = [];
}

glob TIER_RANK: dict[str, int] = {"STRONG": 3, "MEDIUM": 2, "WEAK": 1};

def tier_rank(tier: str) -> int {
    return TIER_RANK.get(tier, 0);
}

walker Blocker {
    has msg_id: str;
    has surnames: list[str] = [];
    # incident id -> tags such as "phone~0775550101" or "name~kumari perera"
    has reached: dict[str, list[str]] = {};

    def note(inc: Incident, tag: str) {
        if inc.status == "RESOLVED" {
            return;
        }
        tags = self.reached.get(inc.inc_id, []);
        if tag not in tags {
            tags.append(tag);
        }
        self.reached[inc.inc_id] = tags;
    }

    can start with Message entry {
        visit [->:HasPhone:->];
        visit [->:Names:->];
        visit [->:At:->];
    }

    can on_phone with Phone entry {
        for m in [here <-:HasPhone:<-[?:Message]] {
            if m.msg_id == self.msg_id {
                continue;
            }
            for inc in [m ->:PartOf:->[?:Incident]] {
                self.note(inc, "phone~" + here.number);
            }
        }
    }

    can on_name with PersonName entry {
        if not is_full_name(here.canonical) {
            return;
        }
        for m in [here <-:Names:<-[?:Message]] {
            if m.msg_id == self.msg_id {
                continue;
            }
            for inc in [m ->:PartOf:->[?:Incident]] {
                self.note(inc, "name~" + here.canonical);
            }
        }
    }

    can on_place with Place entry {
        for m in [here <-:At:<-[?:Message]] {
            if m.msg_id == self.msg_id {
                continue;
            }
            if here.level == "HOUSEHOLD" {
                for inc in [m ->:PartOf:->[?:Incident]] {
                    self.note(inc, "house~" + here.name);
                }
            } else {
                # road or village: only a weak signal, and only with a shared surname
                for pn in [m ->:Names:->[?:PersonName]] {
                    sn = surname_of(pn.canonical);
                    if sn != "" and sn in self.surnames {
                        for inc in [m ->:PartOf:->[?:Incident]] {
                            self.note(inc, "area~" + here.name + "~" + sn);
                        }
                    }
                }
            }
        }
    }
}

def tag_values(tags: list[str], kind: str) -> list[list[str]] {
    out: list[list[str]] = [];
    for t in tags {
        parts = t.split("~");
        if parts[0] == kind {
            out.append(parts[1:]);
        }
    }
    return out;
}

# Turn the walker's tags into one CandInfo per incident (strongest first).
def evaluate_tags(reached: dict[str, list[str]]) -> list[CandInfo] {
    infos: list[CandInfo] = [];
    for inc_id in reached.keys() {
        tags = reached[inc_id];
        phones = tag_values(tags, "phone");
        names = tag_values(tags, "name");
        houses = tag_values(tags, "house");
        areas = tag_values(tags, "area");
        reasons: list[str] = [];
        tier = "WEAK";
        for p in phones {
            reasons.append("[STRONG] exact phone match " + phone_display(p[0]));
            tier = "STRONG";
        }
        if len(names) > 0 and len(houses) > 0 {
            reasons.append(
                "[STRONG] same full name '" + title_case(names[0][0])
                + "' + same household place '" + household_display(houses[0][0]) + "'"
            );
            tier = "STRONG";
        } elif len(names) > 0 {
            reasons.append(
                "[MEDIUM] same full name '" + title_case(names[0][0])
                + "' but no shared household-level place"
            );
            if tier != "STRONG" {
                tier = "MEDIUM";
            }
        } elif len(houses) > 0 {
            reasons.append(
                "[MEDIUM] same household-level place '" + household_display(houses[0][0])
                + "' but no matching name or phone"
            );
            if tier != "STRONG" {
                tier = "MEDIUM";
            }
        }
        for a in areas {
            reasons.append(
                "[WEAK] same surname '" + title_case(a[1]) + "' on the same road or village '"
                + title_case(a[0]) + "' (never a strong detail)"
            );
        }
        infos.append(CandInfo(inc_id=inc_id, tier=tier, reasons=reasons));
    }
    return sorted(
        infos,
        key=lambda (c: CandInfo) { to_int(c.inc_id) - tier_rank(c.tier) * 100000; }
    );
}

# Run the Blocker on a message and write its Candidate edges.
def find_candidates(hub: EkataHub, msg: Message) -> list[CandInfo] {
    surnames: list[str] = [];
    for pn in [msg ->:Names:->[?:PersonName]] {
        sn = surname_of(pn.canonical);
        if sn != "" and sn not in surnames {
            surnames.append(sn);
        }
    }
    walked = msg spawn Blocker(msg_id=msg.msg_id, surnames=surnames);
    infos = evaluate_tags(walked.reached);
    for info in infos {
        inc = find_incident(hub, info.inc_id);
        if inc is not None {
            msg +>:Candidate(reasons=info.reasons):+> inc;
        }
    }
    return infos;
}

def tier_of(infos: list[CandInfo], inc_id: str) -> str {
    for c in infos {
        if c.inc_id == inc_id {
            return c.tier;
        }
    }
    return "";
}

def in_candidates(infos: list[CandInfo], inc_id: str) -> bool {
    for c in infos {
        if c.inc_id == inc_id {
            return True;
        }
    }
    return False;
}

# The best STRONG candidate (rules-only merge when the resolver says nothing).
def best_strong(infos: list[CandInfo]) -> CandInfo | None {
    for c in infos {
        if c.tier == "STRONG" {
            return c;
        }
    }
    return None;
}

# Referee feedback loop: add the block reason to the Candidate edge the
# resolver picked, so the retry sees it next to the reasons it chose among.
def annotate_candidate(msg: Message, inc: Incident, feedback: str) {
    for e in [edge msg ->:Candidate:-> inc] {
        e.reasons = e.reasons + ["REFEREE BLOCKED the previous pick: " + feedback];
    }
}
