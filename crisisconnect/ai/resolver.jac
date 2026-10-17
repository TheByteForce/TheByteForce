"""Choose among direct Candidate neighbours, then independently score that choice."""
import from crisisconnect.replay_cache { read_cached, record_cached }
import from crisisconnect.schema { Message, Incident, Candidate }
import from crisisconnect.ai.models { strong, last_model }
import from crisisconnect.memory { desk_precedents, pattern_for }

glob resolver_model: any = strong;

obj MatchAssessment {
    has same_household: bool = False;
    has confidence: float = 0.0;
    has reason: str = "";
}
sem MatchAssessment.same_household = "True only if the message refers to this exact household, not merely the same surname, road or village.";
sem MatchAssessment.confidence = "Confidence between 0 and 1; uncertainty must reduce the score.";
sem MatchAssessment.reason = "Explain the exact shared identifiers or the reason this is a different household.";

def assess_match(message: str, incident: str, evidence: list[str], feedback: str) -> MatchAssessment by resolver_model(temperature=0.0, incl_info={"policy": "Return same_household=false if the household is different. An exact phone or a canonical full name PLUS a household-level location is strong evidence. A shared surname or road alone is insufficient. Confidence is 0..1. Explain and respect the referee feedback. A 'desk precedent' line in the evidence says what people decided tonight for similar merges: follow it unless the evidence is stronger, and say so in the reason."});
sem assess_match = "Independently assess whether a new emergency message belongs to an existing household. A shared surname or road is never enough. Respect referee feedback. Return false for a new household.";

walker Resolver {
    has chosen_inc_id: str = "";
    has score: float = 0.0;
    has reason: str = "";
    has model: str = "";
    has block_reason: str = "";
    has message_text: str = "";
    has source: Message | None = None;
    has context: dict[str, any] = {};

    can start with Message entry {
        self.source = here;
        self.message_text = here.text;
        if len([here ->:Candidate:->]) == 0 {
            self.reason = "No candidate incidents: open a new incident.";
            self.model = "rules";
            disengage;
        }
        choices: list[str] = [];
        for inc in [here ->:Candidate:->[?:Incident]] {
            reasons: list[str] = [];
            for e in [edge here ->:Candidate:-> inc] { reasons = reasons + e.reasons; }
            pattern = pattern_for(reasons);
            precedent = desk_precedents(pattern) if pattern != "" else "no precedents";
            choices.append(inc.inc_id + ":" + inc.summary + ":" + inc.place + ":" + str(reasons) + ":precedent=" + precedent);
        }
        self.context = {"message": here.text, "choices": sorted(choices), "feedback": self.block_reason};
        cached: any = read_cached("resolver", self.context);
        if cached is not None {
            value: any = cached["value"];
            self.chosen_inc_id = str(value["chosen_inc_id"]); self.score = float(value["score"]);
            self.reason = str(value["reason"]); self.model = "cached:" + str(cached["model"]);
            disengage;
        }
        visit [->:Candidate:->] by resolver_model(
            intent="Choose the most plausible household for this message. Exact phones and a full name plus household place are strong evidence. Same surname or road is insufficient. Referee feedback: " + self.block_reason,
            select=1
        );
    }

    can assess with Incident entry {
        evidence: list[str] = [];
        if self.source is not None {
            for e in [edge self.source ->:Candidate:-> here] {
                evidence = evidence + e.reasons;
            }
        }
        # Learning from the desk: counts and ids of tonight's decisions on this
        # kind of merge, never old message text. The referee still decides.
        pattern = pattern_for(evidence);
        if pattern != "" {
            evidence = evidence + ["desk precedent (" + pattern + "): " + desk_precedents(pattern)];
        }
        result = assess_match(self.message_text, here.inc_id + ": " + here.summary + "; " + here.place, evidence, self.block_reason);
        self.score = max(0.0, min(1.0, result.confidence));
        self.reason = result.reason;
        self.model = last_model();
        if self.model == "" { self.model = "llm"; }
        if result.same_household { self.chosen_inc_id = here.inc_id; }
        record_cached("resolver", self.context, {"chosen_inc_id": self.chosen_inc_id, "score": self.score, "reason": self.reason, "visited_inc_id": here.inc_id}, self.model);
        disengage;
    }
}
