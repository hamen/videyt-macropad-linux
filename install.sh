#!/usr/bin/env bash
# install.sh — configure a "videyt" mini macropad (USB 1189:8840) on Linux:
# speaker + microphone volume knobs (clean labelled notifications) and a set of
# one-press agent macros.
#
# Idempotent: safe to re-run. Everything is path-configurable; nothing is
# hard-coded to a particular home directory or machine.
#
# Usage:
#   ./install.sh [path-to-config.yaml]     # default: ./macropad.yaml
# Env overrides:
#   BIN_DIR=~/.local/bin   # where macropad-audio / macropad-say install (must be on PATH)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CONFIG="${1:-$REPO_DIR/macropad.yaml}"

# Spare keysym -> macropad-audio action.
# The bracketed f-key is the HID code the device sends (see macropad.yaml); on a
# standard Linux/Xorg evdev keymap it produces the keysym on the left. Verify on
# your system with:  xmodmap -pke | grep -Ei 'XF86Tools|XF86Launch'
# >>> SHORTCUT_TABLE_BEGIN
# Extracted verbatim by tests/keysym-names.test.sh. Keep both markers.
declare -A SHORTCUTS=(
  [XF86Tools]="mic-up"      # f13
  [XF86Launch5]="mic-down"  # f14
  [XF86Launch6]="mic-mute"  # f15
  [XF86Launch7]="spk-mute"  # f16
  [XF86Launch8]="spk-down"  # f17
  [XF86Launch9]="spk-up"    # f18
)
# >>> SHORTCUT_TABLE_END

# Single spare keysym -> macropad-say phrase (row 2, plus the first key of row 3).
# Use a plain keysym, NEVER a modifier chord: a chord (Ctrl+Alt+Shift+key) can
# latch the modifiers stuck at the X level and wedge the whole desktop.
#
# This machine has no touchpad, so XF86TouchpadToggle/On/Off are inert and free;
# if you have a touchpad, pick other spare, side-effect-free keysyms for those
# three (the loop below skips them on a laptop, so nothing fights your touchpad).
#
# XF86Favorites is the fourth macro key, reached by the NAMED `favorites` key in
# ch57x-keyboard-tool. f13-f24 were already spent: f13-f18 drive the knobs,
# f21-f23 are the three above, f20 is XF86AudioMicMute (a global handler eats it),
# and f19/f24 carry no keysym on a stock Xorg keymap.
#
# CHECK A CANDIDATE KEYSYM IN THIS ORDER. The first check is the one that matters,
# and it is the one this project learned the hard way — a key shipped completely
# dead because it passed the other two:
#   1. Your desktop must be able to PARSE THE NAME. XFCE resolves a shortcut name
#      through GTK; if GTK does not know it, xfsettingsd never installs the grab.
#      No error — the shortcut sits in xfconf looking correct and does nothing.
#      tests/keysym-names.test.sh runs this check for every keysym below.
#   2. It must exist in the X keymap:  xmodmap -pke | grep -i favorites
#   3. Nothing else may claim it:
#        xfconf-query -c xfce4-keyboard-shortcuts -l | grep -i favorites
# Checks 2 and 3 BOTH passed for the previous keysym (SunProps) while the key was
# dead. Presence in the X keymap does not imply GTK knows the name.
# >>> MACRO_TABLE_BEGIN
# Everything down to the closing marker is extracted verbatim and executed by
# tests/touchpad-guard.test.sh, so the test asserts against THESE declarations
# rather than a copy of them. Keep both markers, each on its own line.
declare -A MACROS=(
  [XF86TouchpadToggle]="go"
  [XF86TouchpadOn]="merge"
  [XF86TouchpadOff]="stop"
  [XF86Favorites]="round"
)

# Keysyms in MACROS that are touchpad keys, and so must not be bound on a machine
# that actually has a touchpad. Everything else in MACROS binds either way.
TOUCHPAD_KEYSYMS=" XF86TouchpadToggle XF86TouchpadOn XF86TouchpadOff "
# >>> MACRO_TABLE_END

# Keysyms this project used to bind and no longer does. install.sh only ever wrote
# shortcuts, so a rename left the old property behind as a dead entry forever.
# Removed after a successful upload, and only when the value still looks like one
# this installer wrote — a binding you made yourself on the same keysym is kept.
RETIRED_KEYSYMS="SunProps"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# 0. Refuse to bind a keysym the desktop cannot parse ------------------------
# The failure this prevents is silent. XFCE resolves a shortcut name through GTK,
# and an unknown name means xfsettingsd never installs the grab: the property is
# written, looks correct, and the key does nothing. This project shipped exactly
# that. Exit non-zero rather than warn and continue — "warned, exited 0, key
# dead" is the bug, not the fix.
# Prints the unparseable names, or a line starting with SKIP if it could not check.
unparseable_keysyms() {
  command -v python3 >/dev/null 2>&1 || { echo "SKIP python3 not found"; return 0; }
  python3 - "$@" <<'PYEOF' 2>/dev/null || echo "SKIP python3-gi (GObject introspection) not available"
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
print(" ".join(n for n in sys.argv[1:] if Gdk.keyval_from_name(n) == Gdk.KEY_VoidSymbol))
PYEOF
}

# 1. ch57x-keyboard-tool ----------------------------------------------------
if ! command -v ch57x-keyboard-tool >/dev/null 2>&1; then
  log "Installing ch57x-keyboard-tool (via cargo)…"
  command -v cargo >/dev/null 2>&1 || { warn "cargo not found — install Rust: https://rustup.rs"; exit 1; }
  cargo install ch57x-keyboard-tool
fi
TOOL="$(command -v ch57x-keyboard-tool)"

# 2. helpers ----------------------------------------------------------------
log "Installing helpers (macropad-audio, macropad-say) to $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_DIR/bin/macropad-audio" "$BIN_DIR/macropad-audio"
install -m 0755 "$REPO_DIR/bin/macropad-say" "$BIN_DIR/macropad-say"
case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) warn "$BIN_DIR is not on your PATH — add it to your shell profile" ;; esac
command -v xdotool >/dev/null 2>&1 || warn "xdotool not found — the agent macros (macropad-say) need it on X11/Xwayland; on native Wayland use wtype/ydotool"

# 3. Desktop shortcuts (XFCE) ----------------------------------------------
bad_keysyms="$(unparseable_keysyms "${!MACROS[@]}" "${!SHORTCUTS[@]}")"
case "$bad_keysyms" in
  SKIP*)
    warn "Cannot check keysym names (${bad_keysyms#SKIP }). If a shortcut silently never fires, this is the first thing to check — install python3-gi and re-run."
    ;;
  "") : ;;
  *)
    warn "These keysyms are not names your desktop can parse: ${bad_keysyms# }"
    warn "GTK maps them to VoidSymbol, so xfsettingsd would never install the grab: the shortcut"
    warn "would appear in xfconf and the key would silently do nothing. Pick a name GTK knows"
    warn "(see the notes above MACROS in this script) and re-run. Nothing was bound."
    exit 1
    ;;
esac

if command -v xfconf-query >/dev/null 2>&1; then
  log "Binding knob keysyms to macropad-audio (XFCE)…"
  for ks in "${!SHORTCUTS[@]}"; do
    cmd="\"$BIN_DIR/macropad-audio\" ${SHORTCUTS[$ks]}"
    if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" >/dev/null 2>&1; then
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -s "$cmd"
    else
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -n -t string -s "$cmd"
    fi
    printf '    %-14s -> %s\n' "$ks" "${SHORTCUTS[$ks]}"
  done

  # >>> BIND_MACROS_BEGIN
  # Everything down to the closing marker is extracted verbatim and executed by
  # tests/touchpad-guard.test.sh. Keep both markers, each on its own line.
  # The default macro keysyms (XF86TouchpadToggle/On/Off) are inert only on a
  # machine with no touchpad. On a laptop they would fight the touchpad, so those
  # three are skipped there — but only those three: every other macro key binds
  # normally. Compute the flag inside an `if`, never as a bare assignment: this
  # script runs under `set -euo pipefail`, and with no touchpad `grep` exits 1,
  # which would abort the whole install before the upload ever runs.
  has_touchpad=false
  if command -v xinput >/dev/null 2>&1 && xinput list 2>/dev/null | grep -qi touchpad; then
    has_touchpad=true
  fi

  bound=0
  skipped=""
  for ks in "${!MACROS[@]}"; do
    if [ "$has_touchpad" = true ] && [[ "$TOUCHPAD_KEYSYMS" == *" $ks "* ]]; then
      skipped="${skipped:+$skipped }$ks"
      continue
    fi
    if [ "$bound" -eq 0 ]; then
      log "Binding agent-macro keys to macropad-say (XFCE)…"
    fi
    cmd="\"$BIN_DIR/macropad-say\" ${MACROS[$ks]}"
    if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" >/dev/null 2>&1; then
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -s "$cmd"
    else
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -n -t string -s "$cmd"
    fi
    printf '    %-22s -> macropad-say %s\n' "$ks" "${MACROS[$ks]}"
    bound=$((bound + 1))
  done
  if [ -n "$skipped" ]; then
    warn "Touchpad detected — skipped these touchpad keysyms: $skipped. The other macro keys were bound. Give those phrases your own spare keysyms in MACROS (install.sh) and re-run."
  fi
  # >>> BIND_MACROS_END

  # 4. Silence the panel's own volume OSD so it doesn't duplicate ours -------
  plugin=""
  for p in $(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null | grep -E '/plugins/plugin-[0-9]+$'); do
    [ "$(xfconf-query -c xfce4-panel -p "$p" 2>/dev/null)" = "pulseaudio" ] && { plugin="$p"; break; }
  done
  if [ -n "$plugin" ]; then
    log "Disabling duplicate volume OSD ($plugin/show-notifications=false)"
    xfconf-query -c xfce4-panel -p "$plugin/show-notifications" -n -t bool -s false 2>/dev/null \
      || xfconf-query -c xfce4-panel -p "$plugin/show-notifications" -s false
  fi
else
  warn "xfconf-query not found (not XFCE?). Bind these yourself to the commands:"
  for ks in "${!SHORTCUTS[@]}"; do printf '    %-22s -> %s/macropad-audio %s\n' "$ks" "$BIN_DIR" "${SHORTCUTS[$ks]}"; done
  for ks in "${!MACROS[@]}"; do printf '    %-22s -> %s/macropad-say %s\n' "$ks" "$BIN_DIR" "${MACROS[$ks]}"; done
  warn "If this machine HAS a touchpad, do not bind XF86TouchpadToggle/On/Off — pick your own spare keysyms for those phrases."
fi

# 5. Upload the key map to the device --------------------------------------
log "Validating config"
"$TOOL" validate < "$CONFIG"
log "Uploading to the macropad (needs root for USB access)…"
sudo "$TOOL" upload < "$CONFIG"

# 6. Drop shortcuts this project used to write and no longer does -----------
# Deliberately AFTER the upload: if the sudo prompt above is cancelled, the device
# still sends the old code, so removing its binding here would leave that key dead
# for a reason the user never asked for. Only values shaped like one this
# installer wrote are removed, so your own binding on the same keysym survives.
# >>> RETIRED_PRUNE_BEGIN
# Extracted verbatim by tests/prune.test.sh. Keep both markers.
if command -v xfconf-query >/dev/null 2>&1; then
  for ks in $RETIRED_KEYSYMS; do
    old="$(xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" 2>/dev/null)" || continue
    # Match the WHOLE value, not a substring. This deletes user configuration, so
    # anything less exact is a bug: a loose match would also eat a command of
    # their own that merely mentions macropad-say, such as
    #   notify-send hi; "/tmp/macropad-say" round
    # The shape this installer writes, and the only shape removed, is exactly:
    #   "<path>/macropad-say" <single-lowercase-word>
    if [[ "$old" =~ ^\"[^\"]*/macropad-say\"[[:space:]][a-z]+$ ]]; then
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -r 2>/dev/null \
        && log "Removed the retired shortcut /commands/custom/$ks"
    else
      warn "Left /commands/custom/$ks alone — it does not look like one this installer wrote: $old"
    fi
  done
fi
# >>> RETIRED_PRUNE_END

log "Done. Turn a knob for a labelled notification; press a macro key (row 2, or row 3 col 1) to type a phrase."
