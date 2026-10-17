
glob captured_spans: list[dict[str, any]] = [];
def capture_span(row: dict[str, any]) -> None {
    captured_spans.append(row);
}


test "native spans retain hierarchy and tool result without inventing usage" {
    import from jaclang.byllm.telemetry { register_agent_callback, _current_invocation_id }
    register_agent_callback(capture_span);
    import from crisisconnect.ai.triage { Ranker }
    captured_spans.clear();
    prior = _current_invocation_id.get(None);
    with NativeSpan(name="test_workflow") as parent {
        ranker = Ranker(rows=[]);
        assert ranker.waiting_time("missing") == "unknown";
        parent_id = parent.run._invocation_id;
    }
    child = captured_spans[-2];
    assert child["parent_invocation_id"] == parent_id;
    assert child["caller_name"] == "waiting_time";
    assert child["caller_args"]["inc_id"] == "missing";
    assert child["agent_response"] == "unknown";
    assert child["tokens"]["requests"] == 0;
    assert child["latency_ms"] >= 0;
    assert _current_invocation_id.get(None) == prior;
}

test "native error spans propagate failure and restore the invocation context" {
    import from jaclang.byllm.telemetry { register_agent_callback, _current_invocation_id }
    register_agent_callback(capture_span);
    captured_spans.clear();
    prior = _current_invocation_id.get(None);
    failed = False;
    try {
        with NativeSpan(name="failing_tool", kind="tool") {
            raise ValueError("test outage");
        }
    } except ValueError {
        failed = True;
    }
    assert failed;
    assert captured_spans[-1]["status"] == "error";
    assert "test outage" in captured_spans[-1]["error"];
    assert _current_invocation_id.get(None) == prior;
}

test "Jac native telemetry store accepts the workflow and tool hierarchy" {
    import from jaclang.byllm.telemetry { register_agent_callback, _current_invocation_id }
    register_agent_callback(capture_span);
    import from jaclang.scale.admin.llm_telemetry { TelemetryStore }
    sink = TelemetryStore();
    register_agent_callback(sink.record_agent_completion);
    with NativeSpan(name="native_store_workflow") as parent {
        with NativeSpan(
            name="native_store_tool", kind="tool", args={"incident": "synthetic"}
        ) as child {
            child.finish("evidence found");
            child_id = child.run._invocation_id;
        }
        parent_id = parent.run._invocation_id;
    }
    detail = sink.get_trace(child_id);
    assert detail is not None;
    assert detail["parent_invocation_id"] == parent_id;
    assert detail["agent_response"] == "evidence found";
    assert detail["completed"];
    assert detail["total_tokens"] == 0;
    assert sink.get_trace(parent_id) is not None;
}
