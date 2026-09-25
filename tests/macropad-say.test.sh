#!/usr/bin/env bash
# tests/macropad-say.test.sh — check what bin/macropad-say actually types.
#
# The phrase is the whole point of a macro key, and nothing else looks at it: the
# other tests cover which keysym runs the script, not what the script sends. So
# this puts a fake `xdotool` first on PATH that records every call it gets, and
# asserts on the full list of calls — not on "contains /compact", which would also
# pass if a later change appended a `key Return` and made the key run the command
# on its own. A no-op `sleep` keeps the test fast.
#
# Run:  tests/macropad-say.test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAY="$REPO_DIR/bin/macropad-say"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$*"; }

# --- stubs -------------------------------------------------------------------
# One line per call, arguments separated by a literal "|" so an empty or
# space-carrying argument cannot hide.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/xdotool" <<'STUB'
#!/bin/sh
line=""
for a in "$@"; do line="$line|$a"; done
printf '%s\n' "$line" >> "$XDOTOOL_LOG"
STUB
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/xdotool" "$WORK/bin/sleep"

run_say() { # $1: name -> exit code in $rc, calls in $WORK/calls.log
  export XDOTOOL_LOG="$WORK/calls.log"; : > "$XDOTOOL_LOG"
  rc=0
  PATH="$WORK/bin:$PATH" "$SAY" "$1" > /dev/null 2> "$WORK/stderr.log" || rc=$?
}

# --- the /compact key --------------------------------------------------------
run_say compact
[ "$rc" -eq 0 ] || fail "macropad-say compact exited $rc: $(cat "$WORK/stderr.log")"
# Compare bytes with cmp, not with "$(cat ...)": command substitution strips
# trailing newlines, so a phrase ending in "\n" — which presses Enter — would pass.
printf '%s\n' '|type|--clearmodifiers|--|/compact' > "$WORK/expected.log"
cmp -s "$WORK/expected.log" "$WORK/calls.log" || fail "macropad-say compact: expected exactly one call [$(cat "$WORK/expected.log")], got: $(od -c "$WORK/calls.log" | head -5)"
pass "compact types exactly '/compact' in one xdotool call — no Enter, nothing else"

# --- an unknown name types nothing -------------------------------------------
run_say bogus
[ "$rc" -eq 2 ] || fail "macropad-say bogus: expected exit 2, got $rc"
[ ! -s "$WORK/calls.log" ] || fail "macropad-say bogus typed something: $(cat "$WORK/calls.log")"
pass "an unknown name exits 2 and types nothing"

printf '\n\033[1;32mAll macropad-say tests passed.\033[0m\n'
