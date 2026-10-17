"""Endpoint smoke test: the demo loads and the replay fills the call queue."""

import os;

test "api smoke: load the demo and replay five messages" {
    os.environ["EKATA_AI"] = "off";
    st = load_demo();
    assert st.seeded;
    assert st.position == 0;
    assert st.total > 0;
    last = replay_next(1);
    for i in range(4) {
        last = replay_next(1);
    }
    assert last.position == 5;
    assert not last.locked;
    assert len(last.queue) > 0;
    assert len(call_queue(1)) == len(last.queue);
    assert last.message is not None;
    assert len(last.new_trace) > 0;
    assert len(trace_since(0)) > 0;
    assert len(trace_since(0)) <= 50;
    assert metrics(1).messages == 5;
    assert demo_state(2).position == 5;
}
