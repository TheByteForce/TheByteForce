"""Guided demonstration endpoints (:pub, shared hub). See scenario.jac."""

import from crisisconnect.store { get_hub }
import from crisisconnect.locking { graph_writer }
import from crisisconnect.scenario { ScenarioView, scenario_reset_in, scenario_next_in, scenario_state_in }
import from crisisconnect.memory { reset_memory }

def:pub scenario_reset() -> ScenarioView {
    with graph_writer() {
        v = scenario_reset_in(get_hub());
        reset_memory();
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
