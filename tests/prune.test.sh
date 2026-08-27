#!/usr/bin/env bash
# tests/prune.test.sh — install.sh removes shortcuts it used to write, and nothing else.
#
# This code DELETES user configuration, so the match has to be exact. An earlier
# version matched a substring, which would also have deleted a command the user
# wrote themselves that merely mentions macropad-say, e.g.
#   notify-send hi; "/tmp/macropad-say" round
#
# The prune block is extracted verbatim from install.sh between its markers and
# run against a stubbed xfconf-query backed by a fake property store, so nothing
# touches the real desktop configuration.
#
# Run:  tests/prune.test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$*"; }

awk '/RETIRED_PRUNE_BEGIN/{f=1;next} /RETIRED_PRUNE_END/{f=0} f' "$INSTALL" > "$WORK/prune.sh"
[ -s "$WORK/prune.sh" ] || fail "could not extract the prune block from install.sh — are the RETIRED_PRUNE markers still there?"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/xfconf-query" <<'STUB'
#!/bin/sh
# Fake property store: one file per property under $STORE.
prop=""; remove=0
while [ $# -gt 0 ]; do
  case "$1" in
    -p) prop="$2"; shift 2 ;;
    -r) remove=1; shift ;;
    -c) shift 2 ;;
    *) shift ;;
  esac
done
f="$STORE/$(echo "$prop" | tr '/' '_')"
if [ "$remove" = 1 ]; then
  [ -f "$f" ] || exit 1
  rm -f "$f"; exit 0
fi
[ -f "$f" ] || exit 1
cat "$f"
STUB
chmod +x "$WORK/bin/xfconf-query"

run_prune() { # $1 = keysym list; store pre-seeded by caller
  PATH="$WORK/bin:$PATH" STORE="$WORK/store" bash -c '
    set -euo pipefail
    log()  { printf "==> %s\n" "$*" >&2; }
    warn() { printf "[!] %s\n" "$*" >&2; }
    RETIRED_KEYSYMS="'"$1"'"
    source "$1"
  ' _ "$WORK/prune.sh" 2> "$WORK/err.log" || fail "prune block exited non-zero: $(cat "$WORK/err.log")"
}
seed() { mkdir -p "$WORK/store"; printf '%s' "$2" > "$WORK/store/_commands_custom_$1"; }
exists() { [ -f "$WORK/store/_commands_custom_$1" ]; }

# --- case 1: a value this installer wrote -> removed -------------------------
rm -rf "$WORK/store"; seed SunProps '"/home/ivan/.local/bin/macropad-say" round'
run_prune SunProps
exists SunProps && fail "case 1: an installer-owned shortcut was NOT removed"
pass "installer-owned value is removed"

# --- case 2: the user's own command on the same keysym -> kept ---------------
rm -rf "$WORK/store"; seed SunProps 'notify-send hi; "/tmp/macropad-say" round'
run_prune SunProps
exists SunProps || fail "case 2: a USER-OWNED command was deleted — the match is too loose"
grep -q 'Left /commands/custom/SunProps alone' "$WORK/err.log" || fail "case 2: kept the value but did not say so"
pass "user-owned command that merely mentions macropad-say is kept"

# --- case 2b: trailing extra arguments -> kept -------------------------------
rm -rf "$WORK/store"; seed SunProps '"/home/ivan/.local/bin/macropad-say" round ; rm -rf /tmp/x'
run_prune SunProps
exists SunProps || fail "case 2b: a value with trailing commands was deleted — the match is not anchored"
pass "value with trailing text is kept (match is anchored at both ends)"

# --- case 3: the property does not exist -> silent no-op ---------------------
rm -rf "$WORK/store"; mkdir -p "$WORK/store"
run_prune SunProps
[ -s "$WORK/err.log" ] && fail "case 3: a missing property produced output: $(cat "$WORK/err.log")"
pass "missing property is a silent no-op"

printf '\n\033[1;32mAll prune tests passed.\033[0m\n'
