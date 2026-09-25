#!/usr/bin/env bash
# tests/touchpad-guard.test.sh — cover install.sh's macro-binding guard.
#
# The guard is the only branching logic in install.sh, and on a machine without a
# touchpad (the one this repo was written on) its interesting half never runs. So
# the test stubs `xinput` to fake a touchpad, and stubs `xfconf-query` to record
# what WOULD be bound instead of touching the real desktop configuration.
#
# Both the guard (BIND_MACROS_BEGIN/END) and the macro table (MACRO_TABLE_BEGIN/END)
# are extracted from install.sh and executed, rather than re-implemented here — a
# copy would drift from the real thing and keep passing while install.sh broke.
# That applies to the data as much as to the logic: if the test declared its own
# MACROS, dropping XF86Favorites or XF86Calculator from the real array would not
# fail anything.
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

# --- extract the real macro table --------------------------------------------
awk '/MACRO_TABLE_BEGIN/{f=1;next} /MACRO_TABLE_END/{f=0} f' "$INSTALL" > "$WORK/macros.sh"
[ -s "$WORK/macros.sh" ] || fail "could not extract the macro table from install.sh — are the MACRO_TABLE markers still there?"

# --- the table must actually describe what this repo ships -------------------
# Read the real declarations here too, so a change to install.sh that removes a
# row-3 macro key, or files it under the touchpad skips, fails loudly instead of
# quietly reducing the test to the three keys it started with.
declare -A MACROS=()
TOUCHPAD_KEYSYMS=""
# shellcheck source=/dev/null
source "$WORK/macros.sh"

for pair in XF86Favorites:round XF86Calculator:compact; do
  ks="${pair%%:*}" phrase="${pair#*:}"
  [ "${MACROS[$ks]+set}" = set ] || fail "install.sh no longer maps $ks — a row-3 macro key is gone"
  [ "${MACROS[$ks]}" = "$phrase" ] || fail "install.sh maps $ks to '${MACROS[$ks]}', expected '$phrase'"
  case "$TOUCHPAD_KEYSYMS" in
    *" $ks "*) fail "$ks is listed in TOUCHPAD_KEYSYMS — it is not a touchpad key and would be skipped on every laptop" ;;
  esac
done
for ks in XF86TouchpadToggle XF86TouchpadOn XF86TouchpadOff; do
  [ "${MACROS[$ks]+set}" = set ] || fail "install.sh no longer maps $ks"
  case "$TOUCHPAD_KEYSYMS" in
    *" $ks "*) : ;;
    *) fail "$ks is missing from TOUCHPAD_KEYSYMS — it would be bound on a laptop and fight the touchpad" ;;
  esac
done
pass "install.sh's macro table: XF86Favorites -> round, XF86Calculator -> compact, and only the XF86Touchpad* keys marked skippable"

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
    source "$1"   # the real MACROS / TOUCHPAD_KEYSYMS, extracted from install.sh
    source "$2"   # the real guard, extracted from install.sh
  ' _ "$WORK/macros.sh" "$WORK/guard.sh" > "$WORK/stdout.$1.log" 2> "$WORK/stderr.$1.log"
  # Only the recorded xfconf writes matter here; the block's own progress output
  # goes to stdout.<case>.log so it cannot contaminate the comparison.
  sort "$XFCONF_LOG"
}

# --- case 1: a machine WITH a touchpad ---------------------------------------
# Only the three touchpad keysyms are skipped. The row-3 keys have nothing to do
# with a touchpad, so they must still be bound — the bug this guard was rewritten
# to fix.
expected_on_laptop="$(for ks in "${!MACROS[@]}"; do
  case "$TOUCHPAD_KEYSYMS" in *" $ks "*) continue ;; esac
  echo "$ks"
done | sort)"
got="$(run_guard yes)"
[ "$got" = "$expected_on_laptop" ] || fail "touchpad present: expected [$(echo "$expected_on_laptop" | tr '\n' ' ')], got: [$(echo "$got" | tr '\n' ' ')]"
pass "touchpad present — the row-3 keys bound, the three XF86Touchpad* keys skipped"

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
for ks in XF86Favorites XF86Calculator; do
  case "$warning" in
    *"$ks"*) fail "warning wrongly names $ks as skipped: $warning" ;;
  esac
done
pass "warning names only the three skipped keysyms, and not the row-3 keys"

# --- case 2: a machine WITHOUT a touchpad ------------------------------------
# Everything binds. This also covers the `set -euo pipefail` trap: with no
# touchpad `grep -qi` exits 1, and computing the flag outside conditional context
# would abort the script here instead of binding anything.
got="$(run_guard no)"
expected="$(printf '%s\n' "${!MACROS[@]}" | sort)"
[ "$got" = "$expected" ] || fail "no touchpad: expected every macro keysym bound, got: $(echo "$got" | tr '\n' ' ')"
pass "no touchpad — every macro keysym bound, no early exit under pipefail"

case "$(cat "$WORK/stderr.no.log")" in
  *"Touchpad detected"*) fail "no touchpad: warned about a touchpad anyway" ;;
esac
pass "no touchpad — no spurious warning"

printf '\n\033[1;32mAll touchpad-guard tests passed.\033[0m\n'
