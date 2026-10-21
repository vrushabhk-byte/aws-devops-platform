#!/usr/bin/env bash
set -euo pipefail

missing=0
for cmd in aws terraform kubectl docker git python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'OK   %-10s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf 'MISS %-10s not found\n' "$cmd"
    missing=1
  fi
done

if command -v aws >/dev/null 2>&1; then
  echo
  aws sts get-caller-identity || true
fi

if [[ "$missing" -ne 0 ]]; then
  echo "Install the missing tools before continuing."
  exit 1
fi
