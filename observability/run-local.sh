#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f .env.local ]]; then set -a; source .env.local; set +a; fi
: "${ADMIN_DEFAULT_PASSWORD:?Set ADMIN_DEFAULT_PASSWORD in .env.local}"
: "${JAC_SERVE_AUTH_SECRET:?Set JAC_SERVE_AUTH_SECRET in .env.local}"
export TEMPO_URL=http://127.0.0.1:13200
export LOKI_URL=http://127.0.0.1:13100
export PROMETHEUS_URL=http://127.0.0.1:19090
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:14318
export JAC_SV_NAME=crisisconnect
export EKATA_AI="${EKATA_AI:-off}"
mkdir -p .jac/observability-logs
exec jac run --dev --host 127.0.0.1 -p "${CC_PORT:-8050}" --api-port "${CC_API_PORT:-8051}" main.jac >>.jac/observability-logs/app.log 2>&1
