"""The live situation: incoming reports arrive on their own as time passes.

The first pulse opens with a backlog of reports already in, as if the desk
came on shift mid-evening. After that, one more report arrives every few
seconds of real time until the night's reports run out. Any open screen
drives the pulse; it is idempotent, so several screens pulsing at once do
not speed it up, and replay_in_hub's lock stops overlapping runs.
"""

import time;
import from ekata.locking { graph_writer }
import from ekata.store { get_hub }
import from ekata.seed { ensure_seeded }
import from ekata.fixtures { prepare_replay }
import from ekata.coordinator { replay_in_hub }

glob OPENING_REPORTS: int = 24,
     SECONDS_PER_REPORT: float = 20.0,
     MAX_PER_PULSE: int = 6,
     LIVE: dict[str, float] = {"started": 0.0};

obj LiveState {
    has messages_in: int = 0;
    has total: int = 0;
    has clock: str = "";
    has arriving: bool = True;
}

def:pub situation_pulse(tick: int = 0) -> LiveState {
    with graph_writer() {
        hub = get_hub();
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
