#!/usr/bin/env bash
# install.sh — configure a "videyt" mini macropad (USB 1189:8840) on Linux:
# speaker + microphone volume knobs (clean labelled notifications) and a row of
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

# Single spare keysym -> macropad-say phrase (second row of keys). Use a plain
# keysym, NEVER a modifier chord: a chord (Ctrl+Alt+Shift+key) can latch the
# modifiers stuck at the X level and wedge the whole desktop. This machine has no
# touchpad, so XF86TouchpadToggle/On/Off are inert and free; if you have a
# touchpad, pick three other spare, side-effect-free keysyms.
declare -A MACROS=(
  [XF86TouchpadToggle]="go"
  [XF86TouchpadOn]="merge"
  [XF86TouchpadOff]="stop"
)

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

  # The default macro keysyms (XF86TouchpadToggle/On/Off) are inert only on a
  # machine with no touchpad. On a laptop they would fight the touchpad, so skip
  # binding and let the user pick their own spare keysyms in MACROS.
  if command -v xinput >/dev/null 2>&1 && xinput list 2>/dev/null | grep -qi touchpad \
     && [ -n "${MACROS[XF86TouchpadToggle]:-}" ]; then
    warn "Touchpad detected — skipping the default touchpad-keysym macros. Edit MACROS in install.sh with your own spare keysyms, then re-run."
  else
    log "Binding agent-macro keys to macropad-say (XFCE)…"
    for ks in "${!MACROS[@]}"; do
      cmd="\"$BIN_DIR/macropad-say\" ${MACROS[$ks]}"
      if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" >/dev/null 2>&1; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -s "$cmd"
      else
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -n -t string -s "$cmd"
      fi
      printf '    %-22s -> macropad-say %s\n' "$ks" "${MACROS[$ks]}"
    done
  fi

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
  for chord in "${!MACROS[@]}"; do printf '    %-22s -> %s/macropad-say %s\n' "$chord" "$BIN_DIR" "${MACROS[$chord]}"; done
fi

# 5. Upload the key map to the device --------------------------------------
log "Validating config"
"$TOOL" validate < "$CONFIG"
log "Uploading to the macropad (needs root for USB access)…"
sudo "$TOOL" upload < "$CONFIG"

log "Done. Turn a knob for a labelled notification; press a second-row key to type a phrase."
