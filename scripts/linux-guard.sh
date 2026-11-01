#!/usr/bin/env bash
# Fail if PashtoCore sources import an Apple-only UI framework or read the
# process-global clock or locale. Date() is allowed only in
# SystemDateProvider.swift. The same rules are tested in
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
# Keep this in sync with LinuxGuardTests.matches. Longer NSTimeZone names
# come before local/system/default so systemTimeZone is not cut at system.
pattern='import[[:space:]]+UIKit\b|import[[:space:]]+SwiftUI\b|import[[:space:]]+SwiftData\b|\bDate\(\)|\bDate\.now\b|\btimeIntervalSinceNow\b|\bNSDate(\(\)|\.date\b|\.now\b)|\b(Calendar|TimeZone|Locale|NSCalendar|NSTimeZone|NSLocale)\.(current|autoupdatingCurrent)\b|\bNSTimeZone\.(localTimeZone|systemTimeZone|defaultTimeZone|local|system|default)\b|\bNSLocale\.currentLocale\b|\bNSCalendar\.currentCalendar\b'

set +e
matches="$(grep -R -n -E -I --exclude-dir=Tests --exclude-dir=.build --include='*.swift' -e "$pattern" "$sources")"
status=$?
set -e

if [[ "$status" -ne 0 && "$status" -ne 1 ]]; then
  echo "linux guard: search failed (exit $status)" >&2
  exit "$status"
fi

violations=""
if [[ "$status" -eq 0 ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    file="${line%%:*}"
    rest="${line#*:}"
    content="${rest#*:}"
    if [[ "$(basename "$file")" == "SystemDateProvider.swift" ]]; then
      # Strip only the allowed Date() call. NSDate() must still fail.
      stripped="$(printf '%s' "$content" | sed -E 's/\bDate\(\)//g')"
      if printf '%s\n' "$stripped" | grep -q -E "$pattern"; then
        violations+="$line"$'\n'
      fi
    else
      violations+="$line"$'\n'
    fi
  done <<< "$matches"
fi

if [[ -n "$violations" ]]; then
  printf '%s' "$violations" >&2
  echo "linux guard: PashtoCore uses an Apple-only import or a process-global clock or locale." >&2
  echo "linux guard: Date() is allowed only in SystemDateProvider.swift." >&2
  exit 1
fi

echo "linux guard: ok"
