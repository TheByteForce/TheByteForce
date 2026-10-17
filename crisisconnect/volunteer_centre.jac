"""Volunteer centre: lists which open incidents each volunteer OFFER could serve.

Listing only. It never dispatches; a person decides who calls whom.
"""

import re;
import from crisisconnect.schema { CrisisConnectHub, Message, Incident }
import from crisisconnect.store { all_messages, all_incidents }
import from crisisconnect.seed { SPINE }
import from crisisconnect.referee { OPEN_STATUSES }

glob RESOURCE_WORDS: dict[str, list[str]] = {
    "boat": ["boat"],
    "vehicle": ["van", "lorry", "truck", "tractor", "jeep", "three-wheeler", "three wheeler", "tuk"],
    "food": ["food", "meals", "meal", "rice", "rations", "dry rations", "ration"],
    "water": ["drinking water", "water bottles", "water bottle"],
    "shelter": ["shelter", "hall", "room", "house for families"],
    "medical": ["doctor", "nurse", "first aid", "medicine"]
};

glob RESOURCE_SERVES: dict[str, list[str]] = {
    "boat": ["boat", "rescue"],
    "vehicle": ["rescue", "food", "water"],
    "food": ["food"],
    "water": ["water"],
    "shelter": ["shelter"],
    "medical": ["medical"]
};

obj OfferMatch {
    has offer_msg_id: str;
    has offer_text: str;
    has resource: str;
    has inc_id: str;
    has inc_place: str;
    has same_area: bool;
    has reason: str;
    has priority: float;
}

def has_word(low: str, word: str) -> bool {
    pat = r"\b" + re.escape(word) + r"(?:s|es)?\b";
    return re.search(pat, low) is not None;
}

def offer_resources(text: str) -> list[str] {
    low = text.lower();
    found: list[str] = [];
    for res in RESOURCE_WORDS.keys() {
        for w in RESOURCE_WORDS[res] {
            if has_word(low, w) {
                found.append(res);
                break;
            }
        }
    }
    return found;
}

def offer_areas(text: str) -> list[str] {
    low = text.lower();
    areas: list[str] = [];
    for dist in SPINE.keys() {
        for ds in SPINE[dist] {
            if ds.lower() in low and ds not in areas {
                areas.append(ds);
            }
        }
    }
    if len(areas) == 0 {
        hits = re.findall(r"\b(?:in|near|at|from|around)\s+([A-Z][a-z]{2,})", text);
        for h in hits {
            if h not in areas {
                areas.append(h);
            }
        }
    }
    return areas;
}

def area_in_incident(areas: list[str], inc: Incident) -> bool {
    hay = (inc.place + " " + inc.gn).lower();
    for a in areas {
        if a.lower() in hay {
            return True;
        }
    }
    return False;
}

def match_offers(hub: CrisisConnectHub) -> list[OfferMatch] {
    out: list[OfferMatch] = [];
    open_incs = [i for i in all_incidents(hub) if i.status in OPEN_STATUSES];
    for m in all_messages(hub) {
        if m.kind != "OFFER" {
            continue;
        }
        areas = offer_areas(m.text);
        area_label = areas[0] if len(areas) > 0 else "an unspecified area";
        cands: list[OfferMatch] = [];
        ranks: dict[str, float] = {};
        for res in offer_resources(m.text) {
            serves = RESOURCE_SERVES[res];
            for inc in open_incs {
                overlap = [n for n in inc.needs if n in serves];
                if len(overlap) == 0 or inc.inc_id in ranks {
                    continue;
                }
                same = area_in_incident(areas, inc);
                why = f"{res} offered in {area_label} → {inc.inc_id} needs {', '.join(inc.needs)}";
                if same {
                    why += " (same area)";
                }
                bonus = 20.0 if len(inc.vulnerable) > 0 else 0.0;
                ranks[inc.inc_id] = (100000.0 if same else 0.0) + inc.priority + bonus;
                cands.append(OfferMatch(
                    offer_msg_id=m.msg_id, offer_text=m.text, resource=res,
                    inc_id=inc.inc_id, inc_place=inc.place, same_area=same,
                    reason=why, priority=inc.priority
                ));
            }
        }
        ordered = sorted(cands, key=lambda (c: OfferMatch) { ranks[c.inc_id]; }, reverse=True);
        out.extend(ordered[0:3]);
    }
    return out;
}
