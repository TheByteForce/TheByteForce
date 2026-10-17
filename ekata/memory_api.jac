"""Agent-memory readers (all :pub, read-only, on the shared hub).

  agent_run        the ordered agent steps behind one message
  rule_stats       referee rule R1..R14 counts by outcome
  precedent_stats  desk merge approvals and rejections by match pattern

Readers take a tick argument because the client caches reads for 60 s.
"""

import from ekata.store { get_hub }
import from ekata.memory {
    agent_run_in, rule_stats_in, precedents_in, usage_ledger_in, rule_citations_in,
    AgentRunView, RuleStat, Precedent, LedgerView, RuleCount
}

def:pub agent_run(msg_id: str, tick: int = 0) -> AgentRunView {
    return agent_run_in(get_hub(), msg_id);
}

def:pub rule_stats(tick: int = 0) -> list[RuleStat] {
    return rule_stats_in(get_hub());
}

def:pub precedent_stats(tick: int = 0) -> list[Precedent] {
    return precedents_in(get_hub());
}

def:pub usage_ledger(tick: int = 0) -> LedgerView {
    return usage_ledger_in();
}

def:pub rule_citations(tick: int = 0) -> list[RuleCount] {
    return rule_citations_in();
}
