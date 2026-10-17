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
