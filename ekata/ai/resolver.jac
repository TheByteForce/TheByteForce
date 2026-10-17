"""Resolver agent (A3b): spawned on a Message; chooses among its Candidate edges.

Contract: the coordinator spawns Resolver on the Message node and then reads
chosen_inc_id / score / reason / model. An empty chosen_inc_id means "new incident".
Contract stub: the AI implementation replaces the body; the fields stay.
"""

import from ekata.schema { Message }

walker Resolver {
    has chosen_inc_id: str = "";
    has score: float = 0.0;
    has reason: str = "";
    has model: str = "";

    can start with Message entry {
        self.reason = "stub resolver: no decision";
    }
}
