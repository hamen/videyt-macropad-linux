#!/usr/bin/env bash
# install.sh — configure a "videyt" mini macropad (USB 1189:8840) as a
# speaker + microphone controller on Linux, with clean labelled notifications.
#
# Idempotent: safe to re-run. Everything is path-configurable; nothing is
# hard-coded to a particular home directory or machine.
#
# Usage:
#   ./install.sh [path-to-config.yaml]     # default: ./macropad.yaml
# Env overrides:
#   BIN_DIR=~/.local/bin   # where macropad-audio is installed (must be on PATH)
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

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# 1. ch57x-keyboard-tool ----------------------------------------------------
if ! command -v ch57x-keyboard-tool >/dev/null 2>&1; then
  log "Installing ch57x-keyboard-tool (via cargo)…"
  command -v cargo >/dev/null 2>&1 || { warn "cargo not found — install Rust: https://rustup.rs"; exit 1; }
  cargo install ch57x-keyboard-tool
fi
TOOL="$(command -v ch57x-keyboard-tool)"

# 2. macropad-audio helper --------------------------------------------------
log "Installing macropad-audio to $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_DIR/bin/macropad-audio" "$BIN_DIR/macropad-audio"
case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) warn "$BIN_DIR is not on your PATH — add it to your shell profile" ;; esac

# 3. Desktop shortcuts (XFCE) ----------------------------------------------
if command -v xfconf-query >/dev/null 2>&1; then
  log "Binding knob keysyms to macropad-audio (XFCE)…"
  for ks in "${!SHORTCUTS[@]}"; do
    cmd="$BIN_DIR/macropad-audio ${SHORTCUTS[$ks]}"
    if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" >/dev/null 2>&1; then
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -s "$cmd"
    else
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$ks" -n -t string -s "$cmd"
    fi
    printf '    %-14s -> %s\n' "$ks" "${SHORTCUTS[$ks]}"
  done

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
  warn "xfconf-query not found (not XFCE?). Bind these keysyms yourself to the commands:"
  for ks in "${!SHORTCUTS[@]}"; do printf '    %-14s -> %s macropad-audio %s\n' "$ks" "$BIN_DIR" "${SHORTCUTS[$ks]}"; done
fi

# 5. Upload the key map to the device --------------------------------------
log "Validating config"
"$TOOL" validate < "$CONFIG"
log "Uploading to the macropad (needs root for USB access)…"
sudo "$TOOL" upload < "$CONFIG"

log "Done. Turn a knob — you should see a labelled notification."
