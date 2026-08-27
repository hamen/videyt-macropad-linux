#!/usr/bin/env bash
# tests/touchpad-guard.test.sh — cover install.sh's macro-binding guard.
#
# The guard is the only branching logic in install.sh, and on a machine without a
# touchpad (the one this repo was written on) its interesting half never runs. So
# the test stubs `xinput` to fake a touchpad, and stubs `xfconf-query` to record
# what WOULD be bound instead of touching the real desktop configuration.
#
# It extracts the block between BIND_MACROS_BEGIN/END from install.sh and runs it,
# rather than re-implementing it — a copy would drift from the real thing and pass
# while install.sh broke.
#
# Run:  tests/touchpad-guard.test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$*"; }

# --- extract the real guard --------------------------------------------------
awk '/BIND_MACROS_BEGIN/{f=1;next} /BIND_MACROS_END/{f=0} f' "$INSTALL" > "$WORK/guard.sh"
[ -s "$WORK/guard.sh" ] || fail "could not extract the guard block from install.sh — are the BIND_MACROS markers still there?"

# --- stubs -------------------------------------------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/xfconf-query" <<'STUB'
#!/bin/sh
# Probe (no -s) reports "property missing"; a write records the path and succeeds.
for a in "$@"; do
  if [ "$a" = "-s" ]; then
    for b in "$@"; do case "$b" in /commands/custom/*) echo "${b##*/}" >> "$XFCONF_LOG" ;; esac; done
    exit 0
  fi
done
exit 1
STUB
chmod +x "$WORK/bin/xfconf-query"

make_xinput() { # $1: yes|no
  if [ "$1" = yes ]; then
    printf '#!/bin/sh\necho "  SynPS/2 Synaptics Touchpad   id=12 [slave  pointer  (2)]"\n' > "$WORK/bin/xinput"
  else
    printf '#!/bin/sh\necho "  Logitech USB Mouse   id=12 [slave  pointer  (2)]"\n' > "$WORK/bin/xinput"
  fi
  chmod +x "$WORK/bin/xinput"
}

run_guard() { # $1: yes|no  -> prints bound keysyms, one per line; stderr = warnings
  make_xinput "$1"
  export XFCONF_LOG="$WORK/bound.$1.log"; : > "$XFCONF_LOG"
  PATH="$WORK/bin:$PATH" bash -c '
    set -euo pipefail
    log()  { printf "==> %s\n" "$*" >&2; }
    warn() { printf "[!] %s\n" "$*" >&2; }
    BIN_DIR="$HOME/.local/bin"
    declare -A MACROS=(
      [XF86TouchpadToggle]="go"
      [XF86TouchpadOn]="merge"
      [XF86TouchpadOff]="stop"
      [SunProps]="round"
    )
    TOUCHPAD_KEYSYMS=" XF86TouchpadToggle XF86TouchpadOn XF86TouchpadOff "
    source "$1"
  ' _ "$WORK/guard.sh" > "$WORK/stdout.$1.log" 2> "$WORK/stderr.$1.log"
  # Only the recorded xfconf writes matter here; the block's own progress output
  # goes to stdout.<case>.log so it cannot contaminate the comparison.
  sort "$XFCONF_LOG"
}

# --- case 1: a machine WITH a touchpad ---------------------------------------
# Only the three touchpad keysyms are skipped. SunProps has nothing to do with a
# touchpad, so it must still be bound — the bug this guard was rewritten to fix.
got="$(run_guard yes)"
[ "$got" = "SunProps" ] || fail "touchpad present: expected only SunProps bound, got: $(echo "$got" | tr '\n' ' ')"
pass "touchpad present — SunProps bound, the three XF86Touchpad* keys skipped"

warning="$(cat "$WORK/stderr.yes.log")"
case "$warning" in
  *"Touchpad detected"*) : ;;
  *) fail "touchpad present: expected a 'Touchpad detected' warning, got: $warning" ;;
esac
for ks in XF86TouchpadToggle XF86TouchpadOn XF86TouchpadOff; do
  case "$warning" in *"$ks"*) : ;; *) fail "warning does not name the skipped keysym $ks" ;; esac
done
case "$warning" in
  *"keysyms: XF86"*) : ;;
  *) fail "warning has a stray space before the keysym list: $warning" ;;
esac
case "$warning" in
  *"SunProps"*) fail "warning wrongly names SunProps as skipped: $warning" ;;
esac
pass "warning names only the three skipped keysyms, and not SunProps"

# --- case 2: a machine WITHOUT a touchpad ------------------------------------
# Everything binds. This also covers the `set -euo pipefail` trap: with no
# touchpad `grep -qi` exits 1, and computing the flag outside conditional context
# would abort the script here instead of binding anything.
got="$(run_guard no)"
expected="$(printf 'SunProps\nXF86TouchpadOff\nXF86TouchpadOn\nXF86TouchpadToggle')"
[ "$got" = "$expected" ] || fail "no touchpad: expected all four keysyms bound, got: $(echo "$got" | tr '\n' ' ')"
pass "no touchpad — all four macro keysyms bound, no early exit under pipefail"

case "$(cat "$WORK/stderr.no.log")" in
  *"Touchpad detected"*) fail "no touchpad: warned about a touchpad anyway" ;;
esac
pass "no touchpad — no spurious warning"

printf '\n\033[1;32mAll touchpad-guard tests passed.\033[0m\n'
