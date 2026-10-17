"""Typed views the UI receives. An endpoint's return type is its wire format."""

obj MsgView {
    has msg_id: str;
    has text: str;
    has channel: str = "";
    has storm_time: str = "";
    has kind: str = "";
    has language: str = "";
}

obj QueueRow {
    has inc_id: str;
    has rank: int = 0;
    has priority: float = 0.0;
    has status: str = "NEW";
    has headline: str = "";
    has place: str = "";
    has headcount: int = 0;
    has vulnerable: list[str] = [];
    has msg_count: int = 0;
    has reason: str = "";
    has waiting: str = "";
}

obj CandidateView {
    has inc_id: str;
    has reasons: list[str] = [];
}

obj ProposalView {
    has msg_id: str;
    has inc_id: str;
    has score: float = 0.0;
    has reason: str = "";
    has outcome: str = "";
}

obj CallView {
    has outcome: str;
    has desk: str;
    has storm_time: str = "";
    has note: str = "";
}

obj ChangeView {
    has field: str;
    has old_value: str;
    has new_value: str;
    has msg_id: str;
}

obj TraceRow {
    has seq: int;
    has agent: str;
    has action: str;
    has model: str = "";
    has reason: str = "";
    has outcome: str = "";
    has storm_time: str = "";
    has target: str = "";
    has confidence: float = 0.0;
}

obj IncidentView {
    has inc_id: str;
    has pending: list[ChangeView] = [];
    has status: str = "NEW";
    has priority: float = 0.0;
    has headcount: int = 0;
    has place: str = "";
    has needs: list[str] = [];
    has vulnerable: list[str] = [];
    has summary: str = "";
    has claimed_by: str = "";
    has messages: list[MsgView] = [];
    has candidates: list[CandidateView] = [];
    has proposals: list[ProposalView] = [];
    has calls: list[CallView] = [];
    has trace: list[TraceRow] = [];
}

obj ReplayStep {
    has done: bool = False;
    has locked: bool = False;
    has position: int = 0;
    has total: int = 0;
    has storm_time: str = "";
    has message: MsgView | None = None;
    has queue: list[QueueRow] = [];
    has new_trace: list[TraceRow] = [];
}

obj Metrics {
    has messages: int = 0;
    has rescue_messages: int = 0;
    has incidents: int = 0;
    has calls_needed: int = 0;
    has calls_saved: int = 0;
    has merge_precision: float = 0.0;
    has merge_recall: float = 0.0;
    has pairs_correct: int = 0;
    has pairs_total: int = 0;
    has note: str = "";
}

obj DemoState {
    has seeded: bool = False;
    has position: int = 0;
    has total: int = 0;
    has storm_time: str = "";
    has synthetic: bool = True;
}
