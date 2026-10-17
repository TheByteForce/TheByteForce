"""Ekata graph schema: the shared contract for every module.

All demo data hangs off one EkataHub node on root.shared, so every desk
sees one graph and load_demo can reset it in one sweep.
Node fields use plain strings for statuses and kinds (the enums below
name the allowed values) so persistence and the wire stay simple.
"""

# ---------- Allowed values ----------

enum MsgKind: str {
    SOS = "SOS",
    UPDATE = "UPDATE",
    OFFER = "OFFER",
    APPEAL = "APPEAL",
    RUMOUR = "RUMOUR"
}

enum PlaceLevel: str {
    HOUSEHOLD = "HOUSEHOLD",
    ROAD = "ROAD",
    VILLAGE = "VILLAGE",
    UNKNOWN = "UNKNOWN"
}

enum IncidentStatus: str {
    NEW = "NEW",
    VERIFYING = "VERIFYING",
    CONFIRMED = "CONFIRMED",
    CLOSE_PROPOSED = "CLOSE_PROPOSED",
    HANDED_OVER = "HANDED_OVER",
    RESOLVED = "RESOLVED",
    STALE = "STALE"
}

enum Verdict: str {
    CHECKING = "CHECKING",
    MATCHED = "MATCHED",
    UNVERIFIED = "UNVERIFIED",
    SUSPICIOUS = "SUSPICIOUS",
    LIKELY_SCAM = "LIKELY_SCAM"
}

enum RefereeOutcome: str {
    APPLIED = "APPLIED",
    NEEDS_HUMAN = "NEEDS_HUMAN",
    BLOCKED = "BLOCKED",
    NEW_INCIDENT = "NEW_INCIDENT"
}

# ---------- What the intake agent returns ----------

obj PersonMention {
    has display: str;
    has canonical: str;
}

obj SosReport {
    has kind: MsgKind;
    has people_count: int = 0;
    has vulnerable: list[str] = [];
    has needs: list[str] = [];
    has place_text: str = "";
    has place_level: PlaceLevel = PlaceLevel.UNKNOWN;
    has house_ref: str = "";
    has phones: list[str] = [];
    has names: list[PersonMention] = [];
    has language: str = "en";
    has rescued: bool = False;
    has summary: str = "";
    has confidence: float = 0.0;
    has payee_accounts: list[str] = [];
    has urls: list[str] = [];
    has claimed_office: str = "";
    has asks_credentials: list[str] = [];
    has claims_for_names: list[str] = [];
}

# ---------- Nodes ----------

node EkataHub {
    has name: str = "ekata";
    has replay_pos: int = 0;
    has replay_total: int = 0;
    has decision_seq: int = 0;
    has incident_seq: int = 0;
    has message_seq: int = 0;
    has storm_time: str = "18:00";
    has replay_lock: bool = False;
}

node Message {
    has msg_id: str;
    has text: str;
    has channel: str = "WEB";
    has language: str = "";
    has storm_time: str = "";
    has kind: str = "";
    has seq: int = 0;
}

node Phone {
    has number: str;
}

node PersonName {
    has canonical: str;
    has display: str = "";
}

node Place {
    has name: str;
    has level: str = "UNKNOWN";
}

node Incident {
    has inc_id: str;
    has status: str = "NEW";
    has priority: float = 0.0;
    has headcount: int = 0;
    has needs: list[str] = [];
    has vulnerable: list[str] = [];
    has place: str = "";
    has gn: str = "";
    has summary: str = "";
    has first_seen: str = "";
    has last_seen: str = "";
    has claimed_by: str = "";
}

node CallLog {
    has outcome: str;
    has desk: str;
    has storm_time: str = "";
    has note: str = "";
}

node District {
    has name: str;
}

node DSDivision {
    has name: str;
}

node GNDivision {
    has name: str;
}

node Appeal {
    has appeal_id: str;
    has text: str;
    has channel: str = "WHATSAPP";
    has verdict: str = "CHECKING";
    has reason: str = "";
    has storm_time: str = "";
}

node BankAccount {
    has account: str;
}

node Url {
    has value: str;
}

node ClaimedOfficial {
    has office: str;
    has contact: str = "";
}

node RegistryEntry {
    has office: str;
    has contact: str;
    has kind: str = "OFFICE";
}

node Bulletin {
    has issuer: str;
    has area: str;
    has text: str;
    has issued_at: str = "";
}

node RumourClaim {
    has claim: str;
    has stance: str = "UNCONFIRMED";
    has storm_time: str = "";
}

node Decision {
    has seq: int;
    has agent: str;
    has action: str;
    has reason: str = "";
    has confidence: float = 0.0;
    has model: str = "";
    has outcome: str = "";
    has storm_time: str = "";
    has target: str = "";
}

# ---------- Edges (every edge declares its endpoint types) ----------

edge Holds: EkataHub --> any {}

edge HasPhone: Message --> Phone {}

edge Names: Message --> PersonName {}

edge At: Message --> Place {}

edge Candidate: Message --> Incident {
    has reasons: list[str] = [];
}

edge PartOf: Message --> Incident {
    has score: float = 0.0;
    has reason: str = "";
    has approved_by: str = "";
}

edge Supersedes: Message --> Message {}

edge Contradicts: Message --> Message {
    has field: str = "";
}

edge LocatedIn: Incident --> GNDivision {}

edge InDS: GNDivision --> DSDivision {}

edge InDistrict: DSDivision --> District {}

edge Logged: CallLog --> Incident {}

edge AppealHasPhone: Appeal --> Phone {}

edge PaysTo: Appeal --> BankAccount {}

edge Links: Appeal --> Url {}

edge ClaimsToBe: Appeal --> ClaimedOfficial {}

edge ListedAs: ClaimedOfficial --> RegistryEntry {
    has contact_match: bool = False;
}

edge ClaimsFor: Appeal --> Incident {
    has match_score: float = 0.0;
}

edge Checks: RumourClaim --> Bulletin {
    has stance: str = "";
}

edge About: Decision --> any {}
