#!/usr/bin/env bash
# tests/keysym-names.test.sh — every keysym this project binds must be a name the
# desktop can actually parse.
#
# This exists because of a real bug. A macro key was bound to `SunProps`: the pad
# emitted it, X delivered it (keycode 138), and `xmodmap -pke` listed it — so it
# looked right by every check the project documented. But XFCE resolves a shortcut
# name through GTK, and GTK does not know the name `SunProps`. Gdk.keyval_from_name
# returned VoidSymbol, xfsettingsd never installed the grab, and the key silently
# did nothing. Nothing errored. It shipped, merged, and was reported broken.
#
# The check is one line of GTK, and it is the only one of the three checks that
# would have caught it.
#
# Run:  tests/keysym-names.test.sh
# Set MACROPAD_ALLOW_NO_GI=1 to downgrade "cannot check" to a warning — do NOT do
# that in CI: silently passing is the failure mode this test was written against.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$*"; }

# --- pull the REAL tables out of install.sh ----------------------------------
awk '/MACRO_TABLE_BEGIN/{f=1;next} /MACRO_TABLE_END/{f=0} f'       "$INSTALL" >  "$WORK/tables.sh"
awk '/SHORTCUT_TABLE_BEGIN/{f=1;next} /SHORTCUT_TABLE_END/{f=0} f' "$INSTALL" >> "$WORK/tables.sh"
[ -s "$WORK/tables.sh" ] || fail "could not extract the keysym tables from install.sh — are the MACRO_TABLE / SHORTCUT_TABLE markers still there?"

declare -A MACROS=() SHORTCUTS=()
TOUCHPAD_KEYSYMS=""
# shellcheck source=/dev/null
source "$WORK/tables.sh"

KEYSYMS=("${!MACROS[@]}" "${!SHORTCUTS[@]}")
[ "${#KEYSYMS[@]}" -gt 0 ] || fail "extracted no keysyms at all — the markers are probably mismatched"

# Retired keysyms are deliberately NOT checked: they are names we no longer bind,
# and one of them (SunProps) is unparseable by design — that is why it is retired.

# --- ask GTK, the same way XFCE does -----------------------------------------
out="$(python3 - "${KEYSYMS[@]}" <<'PYEOF' 2>/dev/null || echo "__NOGI__"
import sys
try:
    import gi
    try:
        gi.require_version("Gdk", "3.0")   # xfsettingsd is GTK3
    except ValueError:
        gi.require_version("Gdk", "4.0")
    from gi.repository import Gdk
except Exception:
    sys.exit(1)
# Gdk.KEY_VoidSymbol is 0xFFFFFF (16777215). Writing the constant by hand is how
# this test was nearly broken on arrival: 0x1000000 is one MORE than VoidSymbol,
# so it would have accepted the very keysym that caused the bug.
for n in sys.argv[1:]:
    print(("BAD " if Gdk.keyval_from_name(n) == Gdk.KEY_VoidSymbol else "OK  ") + n)
PYEOF
)"

if [ "$out" = "__NOGI__" ] || [ -z "$out" ]; then
  msg="cannot check keysym names: python3 with GObject introspection (python3-gi) is required"
  if [ "${MACROPAD_ALLOW_NO_GI:-0}" = "1" ]; then
    printf '\033[1;33m[!]\033[0m SKIPPED — %s\n' "$msg"
    printf '\033[1;33m[!]\033[0m This is the check that catches a silently dead shortcut. Do not skip it in CI.\n'
    exit 0
  fi
  fail "$msg (set MACROPAD_ALLOW_NO_GI=1 to downgrade this to a warning)"
fi

bad="$(printf '%s\n' "$out" | awk '/^BAD /{print $2}')"
if [ -n "$bad" ]; then
  printf '%s\n' "$out" | sed 's/^/     /'
  fail "these keysyms are not names GTK can parse, so XFCE would never install their grab and the keys would silently do nothing:$(printf '%s' " $bad" | tr '\n' ' ')"
fi

printf '%s\n' "$out" | sed 's/^/     /'
pass "all ${#KEYSYMS[@]} keysyms in install.sh resolve to a real GTK keyval (none are VoidSymbol)"

printf '\n\033[1;32mAll keysym-name tests passed.\033[0m\n'
