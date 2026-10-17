"""Native Jac 0.37.25 spans. Uses the same context and emitter as Model.invoke.

Workflow/rule spans carry zero model usage; child model calls own their usage.
Full arguments and outputs remain in Jac's administrator-only trace store.
"""
import time;
import logging;
import json;
import from jaclang.scale._optdeps.opentelemetry { HAS_OTEL }
import uuid;
import from types { SimpleNamespace }
import from jaclang.byllm.telemetry { _current_invocation_id, _emit_agent_telemetry }

obj NativeSpan {
    has name: str;
    has kind: str = "workflow";
    has args: dict[str, any] = {};
    has output: str = "completed";
    has run: any = None;
    has token: any = None;
    has started: float = 0.0;
    has distributed: any = None;
    has distributed_context: any = None;

    def __enter__ -> NativeSpan {
        self.started = time.perf_counter();
        if HAS_OTEL {
            import from opentelemetry { trace }
            self.distributed_context = trace.get_tracer("crisisconnect.agents").start_as_current_span(self.name);
            self.distributed = self.distributed_context.__enter__();
            self.distributed.set_attribute("crisisconnect.span.kind", self.kind);
        }
        self.run = SimpleNamespace(
            _invocation_id=str(uuid.uuid4()),
            _parent_invocation_id=_current_invocation_id.get(None),
            _usage_history=[],
            mtir=SimpleNamespace(
                caller=SimpleNamespace(__name__=self.name), args=self.args
            )
        );
        self.token = _current_invocation_id.set(self.run._invocation_id);
        return self;
    }

    def finish(value: any) -> any {
        self.output = str(value);
        return value;
    }

    def __exit__(exc_type: any, exc: any, tb: any) -> bool {
        try {
            _emit_agent_telemetry(
                self.run,
                self.output if exc is None else None,
                self.kind,
                (time.perf_counter() - self.started) * 1000.0,
                "success" if exc is None else "error",
                exc
            );
        } finally {
            _current_invocation_id.reset(self.token);
            if self.distributed is not None {
                self.distributed.set_attribute("jac.invocation_id", self.run._invocation_id);
                self.distributed.set_attribute("crisisconnect.success", exc is None);
                self.distributed_context.__exit__(exc_type, exc, tb);
            }
            logging.getLogger("crisisconnect.observability").info(json.dumps({
                "event": "agent_span", "agent": self.name, "kind": self.kind,
                "invocation_id": self.run._invocation_id,
                "parent_invocation_id": self.run._parent_invocation_id,
                "status": "success" if exc is None else "error",
                "duration_ms": round((time.perf_counter() - self.started) * 1000.0, 2)
            }));
        }
        return False;
    }
}

# Standalone dev servers do not go through the fleet gateway startup hook.
# Initialize the same native exporter when an explicit local endpoint is set.
with entry {
    import os;
    if HAS_OTEL and os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "") != "" {
        import from jaclang.scale.runtime.context.tracing { install_tracing }
        install_tracing(enabled=True, service_name=os.environ.get("JAC_SV_NAME", "crisisconnect"));
    }
}
