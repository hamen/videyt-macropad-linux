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
declare -A SHORTCUTS=(
  [XF86Tools]="mic-up"      # f13
  [XF86Launch5]="mic-down"  # f14
  [XF86Launch6]="mic-mute"  # f15
  [XF86Launch7]="spk-mute"  # f16
  [XF86Launch8]="spk-down"  # f17
  [XF86Launch9]="spk-up"    # f18
)

# Single spare keysym -> macropad-say phrase (row 2, plus the first key of row 3).
# Use a plain keysym, NEVER a modifier chord: a chord (Ctrl+Alt+Shift+key) can
# latch the modifiers stuck at the X level and wedge the whole desktop.
#
# This machine has no touchpad, so XF86TouchpadToggle/On/Off are inert and free;
# if you have a touchpad, pick other spare, side-effect-free keysyms for those
# three (the loop below skips them on a laptop, so nothing fights your touchpad).
#
# SunProps is the fourth macro key. It is what the f13-f24 range had left: f13-f18
# drive the knobs, f21-f23 are the three above, f20 is XF86AudioMicMute (a global
# handler eats it), and f19/f24 carry no keysym on a stock Xorg keymap, so nothing
# can bind them. Verify SunProps is free on YOUR machine before trusting it:
#   xmodmap -pke | grep -i props
#   xfconf-query -c xfce4-keyboard-shortcuts -l | grep -i props
declare -A MACROS=(
  [XF86TouchpadToggle]="go"
  [XF86TouchpadOn]="merge"
  [XF86TouchpadOff]="stop"
  [SunProps]="round"
)

# Keysyms in MACROS that are touchpad keys, and so must not be bound on a machine
# that actually has a touchpad. Everything else in MACROS binds either way.
TOUCHPAD_KEYSYMS=" XF86TouchpadToggle XF86TouchpadOn XF86TouchpadOff "

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

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

log "Done. Turn a knob for a labelled notification; press a macro key (row 2, or row 3 col 1) to type a phrase."
