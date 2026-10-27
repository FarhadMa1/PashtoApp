#!/usr/bin/env bash
# Fail if PashtoCore sources import an Apple-only UI framework or read the
# process-global clock or locale. The same rules are tested in
# Packages/PashtoCore/Tests/PashtoCoreTests/LinuxGuardTests.swift.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sources="$root/Packages/PashtoCore"

if [[ ! -d "$sources/Sources" ]]; then
  echo "linux guard: PashtoCore sources not found at $sources" >&2
  exit 1
fi

file_count="$(find "$sources" -type d \( -name Tests -o -name .build \) -prune -o -type f -name '*.swift' -print | wc -l)"
if [[ "$file_count" -lt 1 ]]; then
  echo "linux guard: no Swift sources found under $sources" >&2
  exit 1
fi

# GNU grep -E has no \s. [[:space:]] is the whitespace class.
pattern='import[[:space:]]+UIKit\b|import[[:space:]]+SwiftUI\b|import[[:space:]]+SwiftData\b|\bDate\(\)|\bCalendar\.current\b|\bTimeZone\.current\b|\bLocale\.current\b'

set +e
matches="$(grep -R -n -E -I --exclude-dir=Tests --exclude-dir=.build --include='*.swift' -e "$pattern" "$sources")"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  printf '%s\n' "$matches" >&2
  echo "linux guard: PashtoCore uses an Apple-only import or a process-global clock or locale." >&2
  exit 1
fi
if [[ "$status" -ne 1 ]]; then
  echo "linux guard: search failed (exit $status)" >&2
  exit "$status"
fi

echo "linux guard: ok"
