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

sed -i.bak -E "s/(\"version\"\s*:\s*\")[^\"]+(\")/\1${version_name}\2/" library/oh-package.json5
rm -f library/oh-package.json5.bak

ohpm config set registry "https://ohpm.openharmony.cn/ohpm/" || true
ohpm install

if command -v hvigorw >/dev/null 2>&1; then
  hvigorw --stop-daemon >/dev/null 2>&1 || true
fi
if command -v hvigor >/dev/null 2>&1; then
  hvigor --stop-daemon >/dev/null 2>&1 || true
fi

if command -v hvigorw >/dev/null 2>&1; then
  hvigorw --mode module -p module=library assembleHar --no-daemon
elif command -v hvigor >/dev/null 2>&1; then
  hvigor --mode module -p module=library assembleHar --no-daemon
elif [[ -x "./hvigorw" ]]; then
  ./hvigorw --mode module -p module=library assembleHar --no-daemon
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
