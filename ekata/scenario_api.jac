"""Guided demonstration endpoints (:pub, shared hub). See scenario.jac."""

import from ekata.store { get_hub }
import from ekata.locking { graph_writer }
import from ekata.scenario { ScenarioView, scenario_reset_in, scenario_next_in, scenario_state_in }

def:pub scenario_reset() -> ScenarioView {
    with graph_writer() {
        v = scenario_reset_in(get_hub());
        commit();
        return v;
    }
}

def:pub scenario_next() -> ScenarioView {
    with graph_writer() {
        v = scenario_next_in(get_hub());
        commit();
        return v;
    }
}

def:pub scenario_state(tick: int = 0) -> ScenarioView {
    return scenario_state_in(get_hub());
}
