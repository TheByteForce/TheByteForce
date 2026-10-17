"""The live situation: incoming reports arrive on their own as time passes.

The first pulse opens with a backlog of reports already in, as if the desk
came on shift mid-evening. After that, one more report arrives every few
seconds of real time until the night's reports run out. Any open screen
drives the pulse; it is idempotent, so several screens pulsing at once do
not speed it up, and replay_in_hub's lock stops overlapping runs.

A pulse never waits for the writer: if another request is writing (often a
previous pulse with a report at the model), it reports the current state at
once. Each pulse takes in one report, so a desk action waits for at most one.
"""

import time;
import from crisisconnect.scenario { ScenarioState }
import from crisisconnect.schema { Holds }
import from crisisconnect.store { all_messages }
import from crisisconnect.locking { try_graph_writer }
import from crisisconnect.store { get_hub }
import from crisisconnect.seed { ensure_seeded }
import from crisisconnect.fixtures { prepare_replay }
import from crisisconnect.coordinator { replay_in_hub }

glob OPENING_REPORTS: int = 24,
     SECONDS_PER_REPORT: float = 20.0,
     MAX_PER_PULSE: int = 1,
     LIVE: dict[str, float] = {"started": 0.0};

obj LiveState {
    has messages_in: int = 0;
    has total: int = 0;
    has clock: str = "";
    has arriving: bool = True;
}

def:pub situation_pulse(tick: int = 0) -> LiveState {
    with try_graph_writer() as got {
        hub = get_hub();
        if len([hub ->:Holds:->[?:ScenarioState]]) > 0 {
            return LiveState(messages_in=len(all_messages(hub)), total=7, clock=hub.storm_time, arriving=False);
        }
        if not got {
            return LiveState(
                messages_in=hub.replay_pos,
                total=hub.replay_total,
                clock=hub.storm_time,
                arriving=hub.replay_pos < hub.replay_total
            );
        }
        ensure_seeded(hub);
        if hub.replay_total == 0 {
            prepare_replay(hub);
            commit();
        }
        now = time.time();
        if LIVE["started"] == 0.0 {
            LIVE["started"] = now;
        }
        due = OPENING_REPORTS + int((now - LIVE["started"]) / SECONDS_PER_REPORT);
        due = min(due, hub.replay_total);
        behind = due - hub.replay_pos;
        if behind > 0 and not hub.replay_lock {
            replay_in_hub(hub, min(behind, MAX_PER_PULSE));
        }
        return LiveState(
            messages_in=hub.replay_pos,
            total=hub.replay_total,
            clock=hub.storm_time,
            arriving=hub.replay_pos < hub.replay_total
        );
    }
}
