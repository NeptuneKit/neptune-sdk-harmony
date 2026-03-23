#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  cat <<'EOF'
Usage:
  ./scripts/verify-sources-endpoint.sh <base-url> [expected-source-count]

Examples:
  ./scripts/verify-sources-endpoint.sh http://127.0.0.1:18765
  ./scripts/verify-sources-endpoint.sh http://127.0.0.1:18765 1
EOF
  exit 0
fi

base_url="${1%/}"
expected_count="${2:-}"

health_json="$(curl -fsS "${base_url}/v2/export/health")"
sources_json="$(curl -fsS "${base_url}/v2/export/sources")"

node - "$health_json" "$sources_json" "$expected_count" <<'EOF'
const [, , healthArg, sourcesArg, expectedArg] = process.argv;
const health = JSON.parse(healthArg);
const sources = JSON.parse(sourcesArg);
const requiredFields = ['deviceId', 'appId', 'platform', 'sessionId', 'sdkName', 'sdkVersion', 'lastSeenAt'];

if (health.status !== 'ok' && health.status !== 'degraded') {
  throw new Error(`unexpected health status: ${health.status}`);
}

if (!Array.isArray(sources)) {
  throw new Error('sources endpoint must return an array');
}

if (expectedArg.length > 0) {
  const expected = Number.parseInt(expectedArg, 10);
  if (!Number.isFinite(expected)) {
    throw new Error(`invalid expected-source-count: ${expectedArg}`);
  }
  if (sources.length !== expected) {
    throw new Error(`expected ${expected} sources, got ${sources.length}`);
  }
}

for (const [index, source] of sources.entries()) {
  for (const field of requiredFields) {
    if (typeof source[field] !== 'string' || source[field].trim().length === 0) {
      throw new Error(`source[${index}].${field} must be a non-empty string`);
    }
  }
}

console.log(`health.status=${health.status}`);
console.log(`sources.count=${sources.length}`);
EOF
