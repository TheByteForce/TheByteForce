"""The four portals: who each is for, its pages, and the photo on its door.

Each person works in one portal. The sidebar shows only the current portal's
pages; "All portals" leads back to the start page.
"""

import from "@hugeicons/core-free-icons" {
    LifebuoyIcon, Search01Icon, SecurityCheckIcon, MapsIcon, Megaphone01Icon,
    Call02Icon, TruckIcon, InboxIcon, CheckmarkCircle01Icon, Building03Icon,
    DashboardSquare01Icon, Shield01Icon, BookOpen01Icon, Alert02Icon, UserGroupIcon,
    File01Icon, Activity01Icon, ChartLineData01Icon, Message01Icon, Route01Icon
}

glob PORTALS: list[dict[str, any]] = [
    {
        "key": "citizen",
        "name": "Citizen",
        "path": "/citizen",
        "who": "People in the flood and their families",
        "pitch": "Ask for help with your location, track your request and check appeals before you pay.",
        "image": "/static/assets/images/boat-crossing.jpg",
        "imageAlt": "Rescue workers crossing flood water by boat",
        "workspace": "Your area",
        "nav": [
            {"to": "/citizen", "label": "Send an SOS", "icon": LifebuoyIcon},
            {"to": "/citizen/track", "label": "Track my request", "icon": Search01Icon},
            {"to": "/citizen/check", "label": "Check a message", "icon": SecurityCheckIcon},
            {"to": "/citizen/map", "label": "Situation map", "icon": MapsIcon},
            {"to": "/citizen/bulletins", "label": "Official bulletins", "icon": Megaphone01Icon}
        ]
    },
    {
        "key": "officer",
        "name": "Division officer",
        "path": "/officer",
        "who": "Grama Niladhari and divisional desks",
        "pitch": "Call the most vulnerable first, confirm each case by phone and ask relief groups for help.",
        "image": "/static/assets/images/operations-center.jpg",
        "imageAlt": "Operators at their desks in an emergency operations centre",
        "workspace": "Your division",
        "nav": [
            {"to": "/officer", "label": "Call queue", "icon": Call02Icon},
            {"to": "/officer/requests", "label": "Relief requests", "icon": TruckIcon},
            {"to": "/officer/map", "label": "Map and route", "icon": Route01Icon}
        ]
    },
    {
        "key": "ngo",
        "name": "Relief group",
        "path": "/ngo",
        "who": "Registered relief groups and volunteers",
        "pitch": "Accept requests that fit what you offer, plan your run and mark help delivered.",
        "image": "/static/assets/images/volunteers-desk.jpg",
        "imageAlt": "Volunteers helping residents at a disaster recovery centre",
        "workspace": "Your group",
        "nav": [
            {"to": "/ngo", "label": "Requests for you", "icon": InboxIcon},
            {"to": "/ngo/done", "label": "Accepted and delivered", "icon": CheckmarkCircle01Icon},
            {"to": "/ngo/map", "label": "Map and route", "icon": Route01Icon},
            {"to": "/ngo/profile", "label": "Your group", "icon": Building03Icon}
        ]
    },
    {
        "key": "district",
        "name": "District coordination",
        "path": "/district",
        "who": "District secretariat and disaster management",
        "pitch": "See every division at once, escalate waiting cases, check appeals and publish bulletins.",
        "image": "/static/assets/images/officials-meeting.jpg",
        "imageAlt": "Officials around a table at an emergency operations centre",
        "workspace": "Reviewing as",
        "nav": [
            {"to": "/district", "label": "Overview", "icon": DashboardSquare01Icon},
            {"to": "/district/map", "label": "Situation map", "icon": MapsIcon},
            {"to": "/district/messages", "label": "Incoming messages", "icon": Message01Icon},
            {"to": "/district/queue", "label": "All open cases", "icon": Call02Icon},
            {"to": "/district/alerts", "label": "Alert levels", "icon": Alert02Icon},
            {"to": "/district/appeals", "label": "Appeals and rumours", "icon": Shield01Icon},
            {"to": "/district/volunteers", "label": "Volunteer offers", "icon": UserGroupIcon},
            {"to": "/district/registry", "label": "Registry and bulletins", "icon": BookOpen01Icon},
            {"to": "/district/handover", "label": "DS hand-over", "icon": File01Icon},
            {"to": "/district/activity", "label": "Agent activity", "icon": Activity01Icon},
            {"to": "/district/results", "label": "Results", "icon": ChartLineData01Icon}
        ]
    }
];

glob CITIZEN_AREAS: list[str] = [
    "Kegalle", "Mawanella", "Aranayaka", "Rambukkana", "Warakapola", "Yatiyantota", "Ratnapura", "Kuruwita"
];

glob RUN_DIVISIONS: list[str] = [
    "Mawanella", "Kegalle", "Aranayaka", "Rambukkana", "Warakapola", "Yatiyantota",
    "Dehiowita", "Ratnapura", "Kuruwita", "Eheliyagoda"
];

def:pub portal_for(path: str) -> dict[str, any] | None {
    for p in PORTALS {
        if path == p["path"] or path.startswith(p["path"] + "/") {
            return p;
        }
    }
    return None;
}

def:pub all_portals -> list[dict[str, any]] {
    return PORTALS;
}

def:pub citizen_areas -> list[str] {
    return CITIZEN_AREAS;
}

def:pub run_divisions -> list[str] {
    return RUN_DIVISIONS;
}

def:pub officer_desk(ds: str) -> str {
    return "Divisional desk, " + ds;
}
