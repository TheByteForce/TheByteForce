test "observed pool emits one native invocation and counts usage once" {
    import from unittest.mock { patch }
    import from types { SimpleNamespace }
    import from jaclang.byllm.llm { BaseLLM }
    import from jaclang.byllm.telemetry { _current_invocation_id }

    before_calls = usage_totals["calls"];
    before_tokens = usage_totals["tokens"];
    before_log = len(call_log);
    run: any = SimpleNamespace(
        mtir=SimpleNamespace(
            caller=SimpleNamespace(__name__="pool_test"), args={"text": "synthetic"}
        ),
        _usage_history=[
            {
                "prompt_tokens": 7,
                "completion_tokens": 3,
                "total_tokens": 10,
                "cost": 0.001,
                "model": "test-model"
            }
        ]
    );
    previous = _current_invocation_id.get(None);
    with NativeSpan(name="pool_test_workflow") as parent {
        with patch.object(BaseLLM, "invoke", return_value="observed answer") {
            assert fast.invoke(run) == "observed answer";
        }
        assert run._parent_invocation_id == parent.run._invocation_id;
    }
    assert usage_totals["calls"] == before_calls + 1;
    assert usage_totals["tokens"] == before_tokens + 10;
    assert len(call_log) == before_log + 1;
    assert call_log[-1]["invocation_id"] == run._invocation_id;
    assert call_log[-1]["input_tokens"] == 7;
    assert call_log[-1]["output_tokens"] == 3;
    assert _current_invocation_id.get(None) == previous;
}

test "observed pool error emits failure once and restores context" {
    import from unittest.mock { patch }
    import from types { SimpleNamespace }
    import from jaclang.byllm.llm { BaseLLM }
    import from jaclang.byllm.telemetry { _current_invocation_id }

    run: any = SimpleNamespace(
        mtir=SimpleNamespace(caller=SimpleNamespace(__name__="pool_failure"), args={}),
        _usage_history=[]
    );
    previous = _current_invocation_id.get(None);
    before_errors = usage_totals["errors"];
    failed = False;
    try {
        with patch.object(
            BaseLLM, "invoke", side_effect=RuntimeError("provider unavailable")
        ) {
            fast.invoke(run);
        }
    } except RuntimeError {
        failed = True;
    }
    assert failed;
    assert usage_totals["errors"] == before_errors + 1;
    assert call_log[-1]["status"] == "error";
    assert _current_invocation_id.get(None) == previous;
}
