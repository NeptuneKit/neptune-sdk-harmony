#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

version_name="$1"

if [[ ! -f "library/oh-package.json5" ]]; then
  echo "library/oh-package.json5 not found" >&2
  exit 1
fi

# Keep library ArkTS mirror in sync when build runs in a clean CI checkout.
if [[ -x "./scripts/sync-harmony-module.sh" ]]; then
  ./scripts/sync-harmony-module.sh
fi

if [[ ! -f "library/src/main/ets/index.ets" ]]; then
  mkdir -p "library/src/main/ets"
  cat > "library/src/main/ets/index.ets" <<'ETS'
export * from './model/LogModels'
export * from './core/LogStoreBase'
export * from './core/MemoryLogStore'
export * from './core/RdbLogStore'
export * from './core/LogQueue'
export * from './core/LogQueueFactory'
export * from './server/ExportServer'
export * from './ui-tree/ArkUIViewTreeCollector'
export * from './callback'
export * from './discovery'
export * from './ws'
ETS
fi

python3 - <<'PY' "${version_name}"
import pathlib
import re
import sys

version = sys.argv[1]
path = pathlib.Path("library/oh-package.json5")
text = path.read_text(encoding="utf-8")
updated, n = re.subn(
    r'("version"\s*:\s*")[^"]+(")',
    rf"\g<1>{version}\2",
    text,
    count=1,
)
if n != 1:
    raise SystemExit("failed to update version in library/oh-package.json5")
path.write_text(updated, encoding="utf-8")
PY

if ! rg -q "\"version\"[[:space:]]*:[[:space:]]*\"${version_name}\"" library/oh-package.json5; then
  echo "version update verification failed: expected ${version_name}" >&2
  exit 1
fi

ohpm config set registry "https://ohpm.openharmony.cn/ohpm/" || true
ohpm install

if command -v hvigorw >/dev/null 2>&1; then
  hvigorw --stop-daemon >/dev/null 2>&1 || true
fi
if command -v hvigor >/dev/null 2>&1; then
  hvigor --stop-daemon >/dev/null 2>&1 || true
fi

if [[ -x "./hvigorw" ]]; then
  ./hvigorw --mode module -p module=library assembleHar --no-daemon
elif command -v hvigorw >/dev/null 2>&1; then
  hvigorw --mode module -p module=library assembleHar --no-daemon
elif command -v hvigor >/dev/null 2>&1; then
  hvigor --mode module -p module=library assembleHar --no-daemon
else
  echo "Cannot find hvigor/hvigorw for building HAR" >&2
  exit 1
fi

har_path="$(find library/build -type f -name '*.har' | head -n1 || true)"
if [[ -z "${har_path}" || ! -f "${har_path}" ]]; then
  echo "No .har artifact found in library/build" >&2
  exit 1
fi

echo "${har_path}"
