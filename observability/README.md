# CrisisConnect observability (Jac 0.37.25)

The existing persisted agent-memory graph and usage ledger remain authoritative
business records. Native diagnostic traces are additional, process-local records.

## JacHammer

`jac.toml` enables `[scale.monitoring]`, `[scale.tracing]`,
`[scale.gateway.tracing]`, and `[scale.gateway.logs]`. Redeploy the application
after changing these settings; refreshing the admin page does not provision
backends. Run `jac install` before building so tracing extras are installed.

The deployment needs Prometheus for cluster metrics, Tempo for distributed traces,
and Loki plus Alloy for log collection. Jac's Kubernetes deployment provisions
these when the platform permits it. JacHammer operators must allow the monitoring
stack and supply reachable `TEMPO_URL`, `LOKI_URL`, and an OTLP collector endpoint
if the platform overrides deployment defaults. A repository configuration cannot
by itself guarantee that a hosted platform provisions these services.

Sign in at `/admin`. Use Monitoring → Metrics, Services, LLM Metrics, LLM Traces,
Traces, and Logs. Authentication remains enabled. The LLM trace store includes
inputs and outputs, so restrict admin access appropriately.

## Local verification

Use a Linux checkout with Jac 0.37.25, Docker Compose, and the app dependencies:

```bash
jac install
mkdir -p .jac/observability-logs
docker compose -p crisisconnect-observability -f observability/compose.yaml up -d
# Put the existing local admin password in ADMIN_DEFAULT_PASSWORD in ignored .env.local.
# Also set JAC_SERVE_AUTH_SECRET. These values are never committed.
# CRISISCONNECT_AI=off runs rules; real model calls require GEMINI_API_KEY and AI enabled.
bash observability/run-local.sh
```

The app runs at `http://localhost:8050`, API/admin at `http://localhost:8051/admin`.
The runner sends spans to Alloy on 14318; Jac queries Tempo on 13200, Loki on
13100, and Prometheus on 19090. The local Prometheus container uses Linux host
networking to scrape this app's loopback API port 8051; update its scrape target
if changing the API port. Alloy tails only this checkout's `.jac/observability-logs/*.log` files.
It does not mount the Docker socket or collect unrelated applications' logs.
Local labels use namespace `default`, matching Jac's standalone admin filter.
If overriding `[scale.kubernetes].namespace`, update these local labels to match.
The Compose stack is a local ephemeral diagnostic environment, not production
storage. Stop it using the same Compose command with `down`.

Cluster-only pages can show no Kubernetes workloads on a standalone server.
Users, SSO, deployment health, and pod environment are administrative facilities;
enabling observability does not configure an identity provider or a cluster.

## Agent and tool spans

`NativeSpan` follows Jac's native byLLM invocation context and emits completion
records understood by LLM Traces. It wraps message processing, intake, resolver,
resource requests, relief-group actions, ranking tools, and investigation tools.
ModelPool bypasses `Model.invoke` in this Jac release, so `ObservedPool` explicitly
adds the native context and completion event. Call-log rows still feed the
existing memory writer, with token and cost totals counted once.

Workflow/tool spans have zero model usage. Only provider-reported usage is counted;
rules and cached responses do not invent tokens. Tool output and agent output
are inspectable in native traces. Recorded reasons are explanations of decisions,
not hidden model chain-of-thought.

When tracing extras and an exporter are active, the same scopes emit distributed
spans. Structured completion logs contain scope names, IDs, status and duration;
they intentionally omit report text, tool results and credentials.

The adapter uses version-specific Jac internals `_current_invocation_id` and
`_emit_agent_telemetry`. Re-run the tests before upgrading. Current application
agents invoke synchronously; asynchronous/streaming pool calls require a separate
adapter. Native LLM traces are bounded in-memory diagnostics and disappear on
restart; the friend's persisted memory/ledger is retained independently.

```bash
jac test crisisconnect/instrumentation.jac crisisconnect/ai/models.jac crisisconnect/memory.jac
jac check main.jac crisisconnect/instrumentation.jac crisisconnect/ai/models.jac
jac run --faux
```

From Windows, `observability/verify-local.ps1` reads the ignored local admin
password and checks the admin endpoints without printing tokens or trace content.
Use `-TokenFile` to write an admin bearer token to the Linux checkout's
`.jac/observability-secrets/metrics-token` (for example through a WSL UNC path).
The Prometheus container reads this file to authenticate `/metrics`; anonymous
scrapes are forbidden. Grant read access only to the collector user (UID/GID
65534 in this local image), keep the file ignored, and refresh it when the token
expires. This token grants admin access, so do not share it or mount it elsewhere.

`ADMIN_DEFAULT_PASSWORD` is a local script convention, not an automatic Jac
bootstrap override. On a fresh database Jac reads `[scale.admin].default_password`;
configure that through environment interpolation if needed and complete the
initial password-change flow. The verification script never changes passwords.
