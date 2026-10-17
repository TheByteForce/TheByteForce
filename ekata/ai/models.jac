"""Model tiers, budget hook and call telemetry for Ekata's agents.

Two model pools, both with the ordered "fallback" strategy: a call goes to the
first model and moves to the next only when that one fails (rate limit, timeout,
outage). The agents name the pool they use: `by fast(...)` or `by strong(...)`.

  fast   intake (A1), call brief, offer matcher, rumour router
  strong resolver (A3b), ranker, appeal investigator, case writer

Keys come from the environment (GEMINI_API_KEY); nothing is hard-coded here.
"""

import time;
import from jaclang.byllm.lib { Model, ModelPool }
import from jaclang.byllm.types { IterationAction, IterationContext }
import from jaclang.byllm.telemetry { register_agent_callback }

# ---------- Model pools ----------

glob FAST_MODELS: list[str] = ["gemini/gemini-2.5-flash", "gemini/gemini-2.5-flash-lite"],
     STRONG_MODELS: list[str] = ["gemini/gemini-2.5-pro", "gemini/gemini-2.5-flash"];

glob fast = ModelPool(
         models=[
             Model(model_name="gemini/gemini-2.5-flash"),
             Model(model_name="gemini/gemini-2.5-flash-lite")
         ],
         strategy="fallback",
         num_retries=1,
         timeout=30.0
     ),
     strong = ModelPool(
         models=[
             Model(model_name="gemini/gemini-2.5-pro"),
             Model(model_name="gemini/gemini-2.5-flash")
         ],
         strategy="fallback",
         num_retries=1,
         timeout=45.0
     );

# ---------- Budget hook for ReAct agents ----------

glob MAX_REACT_ITERATIONS: int = 4,
     TOKEN_BUDGET: int = 20000,
     COST_BUDGET_USD: float = 0.05,
     MAX_TRACE_ROWS: int = 400;

# One row per tool-call iteration, so a trace can show what an agent looked up.
glob agent_steps: list[dict[str, any]] = [];

"""Stop a ReAct loop that runs past its iteration, token or cost budget.

Used as `by strong(tools=[...], max_react_iterations=MAX_REACT_ITERATIONS,
on_iteration=budget_hook)`. Every call is also recorded in agent_steps."""
def budget_hook(ctx: IterationContext) -> IterationAction {
    agent_steps.append(
        {
            "iteration": ctx.iteration,
            "tool": ctx.last_tool,
            "result_preview": str(ctx.last_result)[:160],
            "tokens": ctx.total_tokens,
            "cost": ctx.total_cost
        }
    );
    if len(agent_steps) > MAX_TRACE_ROWS {
        del agent_steps[0];
    }
    if ctx.iteration >= MAX_REACT_ITERATIONS {
        return IterationAction.ABORT_WITH_SUMMARY;
    }
    if ctx.total_tokens > TOKEN_BUDGET {
        return IterationAction.ABORT_WITH_SUMMARY;
    }
    if ctx.total_cost > COST_BUDGET_USD {
        return IterationAction.ABORT_WITH_SUMMARY;
    }
    return IterationAction.CONTINUE;
}

"""Return and clear the tool-call steps recorded by budget_hook."""
def drain_agent_steps -> list[dict[str, any]] {
    rows = list(agent_steps);
    agent_steps.clear();
    return rows;
}

# ---------- Per-call telemetry (model, latency, tokens) ----------

glob call_log: list[dict[str, any]] = [];

def _record_call(rec: dict[str, any]) -> None {
    tokens = rec.get("tokens") or {};
    per_call = tokens.get("per_call") or [];
    answered_by = str(rec.get("model") or "");
    if len(per_call) > 0 {
        answered_by = str(per_call[-1].get("model") or answered_by);
    }
    total = tokens.get("total") or {};
    call_log.append(
        {
            "caller": str(rec.get("caller_name") or ""),
            "model": answered_by,
            "latency_ms": float(rec.get("latency_ms") or 0.0),
            "total_tokens": int(total.get("total_tokens") or 0),
            "status": str(rec.get("status") or ""),
            "error": str(rec.get("error") or "")
        }
    );
    if len(call_log) > MAX_TRACE_ROWS {
        del call_log[0];
    }
}

"""Model that answered the most recent call of a caller ("" = any caller)."""
def last_model(caller: str = "") -> str {
    for i in range(len(call_log) - 1, -1, -1) {
        row = call_log[i];
        if (caller == "" or row["caller"] == caller) and row["status"] == "success" {
            return str(row["model"]);
        }
    }
    return "";
}

"""Telemetry rows of successful calls: count, median-free totals for cost notes."""
def call_stats -> dict[str, any] {
    ok = [r for r in call_log if r["status"] == "success"];
    return {
        "calls": len(call_log),
        "ok": len(ok),
        "errors": len(call_log) - len(ok),
        "tokens": sum([int(r["total_tokens"]) for r in ok]),
        "latency_ms": sum([float(r["latency_ms"]) for r in ok])
    };
}

with entry {
    register_agent_callback(_record_call);
}
