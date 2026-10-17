import from crisisconnect.evaluation { EvaluationReport, latest_report }
import from crisisconnect.ai.models { call_stats }

def:pub evaluation_results(tick: int = 0) -> EvaluationReport | None { return latest_report(); }

def:pub model_usage(tick: int = 0) -> dict[str, any] { return call_stats(); }
