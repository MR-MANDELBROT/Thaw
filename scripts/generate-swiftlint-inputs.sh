#!/usr/bin/env bash
# Regenerates scripts/swiftlint-inputs.xcfilelist from tracked Swift sources
# in the same modules SwiftLint lints (see .swiftlint.yml).
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
output="${1:-$root/scripts/swiftlint-inputs.xcfilelist}"

cd "$root"

git ls-files --cached --others --exclude-standard '*.swift' \
    | while IFS= read -r file; do
        [[ -f "$file" ]] && printf '%s\n' "$file"
    done \
    | grep -E '^(MenuBarModel|Shared|Thaw|ThawAX|ThawCapture|ThawCtl|ThawLayout|ThawUI)/' \
    | sort \
    | sed 's|^|$(SRCROOT)/|' \
    > "$output"
