#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "${script_dir}/.." && pwd)
source_dir="${repo_root}/src/main/ets"
target_dir="${repo_root}/library/src/main/ets"

if [ ! -d "${source_dir}" ]; then
  echo "source ets directory not found: ${source_dir}" >&2
  exit 1
fi

mkdir -p "${repo_root}/library/src/main"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "${source_dir}/" "${target_dir}/"
  exit 0
fi

if [ -L "${target_dir}" ]; then
  unlink "${target_dir}"
fi

rm -rf "${target_dir}"
mkdir -p "${target_dir}"
cp -R "${source_dir}/." "${target_dir}/"
