"""Plain-language labels shared by every page."""

def:pub pretty(s: str) -> str {
    if s == "" {
        return "";
    }
    words = " ".join(s.split("_")).lower();
    return words[0].upper() + words[1:];
}

def:pub plural(n: int, one: str, many: str) -> str {
    return f"{n} {one}" if n == 1 else f"{n} {many}";
}

def:pub people_label(n: int) -> str {
    if n <= 0 {
        return "Headcount unknown";
    }
    return plural(n, "person", "people");
}

def:pub place_label(place: str) -> str {
    return place if place != "" else "Place unknown";
}

def:pub call_outcome_label(outcome: str) -> str {
    if outcome == "REACHED_CONFIRMED" {
        return "Reached, confirmed";
    }
    if outcome == "NO_ANSWER" {
        return "No answer";
    }
    if outcome == "RESCUED" {
        return "Rescued";
    }
    if outcome == "STILL_IN_NEED" {
        return "Still in need";
    }
    return pretty(outcome);
}

def:pub referee_label(outcome: str) -> str {
    if outcome == "APPLIED" {
        return "Applied";
    }
    if outcome == "NEEDS_HUMAN" {
        return "Needs a person";
    }
    if outcome == "BLOCKED" {
        return "Blocked";
    }
    if outcome == "NEW_INCIDENT" {
        return "New incident";
    }
    if outcome == "" {
        return "Pending";
    }
    return pretty(outcome);
}

def:pub channel_label(channel: str) -> str {
    if channel == "WHATSAPP" {
        return "WhatsApp";
    }
    if channel == "HOTLINE" {
        return "Hotline";
    }
    if channel == "WEB" {
        return "Web";
    }
    return channel;
}

# Agent families for filtering the activity log.
def:pub agent_group(agent: str) -> str {
    if agent in ["ranker", "priority", "call_brief"] {
        return "ranker";
    }
    if agent in ["referee", "referee_merge", "referee_merge_retry", "appeal_referee"] {
        return "referee";
    }
    if agent == "blocking" {
        return "resolver";
    }
    if agent in ["intake", "resolver", "matcher", "officer", "ngo"] {
        return agent;
    }
    return "other";
}

glob AGENT_NAMES: dict[str, str] = {
    "intake": "Intake agent",
    "blocking": "Candidate finder",
    "resolver": "Resolver agent",
    "ranker": "Ranking agent",
    "priority": "Ranking agent",
    "call_brief": "Call brief agent",
    "matcher": "Matching agent",
    "router": "Route agent",
    "referee": "Referee",
    "referee_merge": "Referee",
    "referee_merge_retry": "Referee",
    "appeal_referee": "Appeal referee",
    "appeal_investigator": "Appeal investigator",
    "officer": "Divisional officer",
    "ngo": "Relief group",
    "desk": "Call desk",
    "analyst": "Analyst",
    "district": "District office",
    "citizen": "Citizen",
    "freshness": "Freshness check"
};

def:pub agent_name(agent: str) -> str {
    return AGENT_NAMES[agent] or pretty(agent);
}
