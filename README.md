# videyt mini macropad on Linux — speaker + microphone knobs

Turn a cheap "Mini Keyboard" macropad (the ones whose manual only ships a
**Windows** app from `videyt.com`) into a tidy **speaker + microphone controller
on Linux** — with clean, labelled desktop notifications and **no background
daemon**.

This is the pad sold under a dozen brands: **15 keys + 2 rotary knobs**, showing
up on USB as:

```
ID 1189:8840  USB Composite Device
```

The official customization software is Windows only. You don't need it. The knob
mapping is written straight to the device over USB and stored **on the device**,
so it survives reboots and works on any machine afterwards.

**What you get**

| Knob        | Turn                 | Press            |
|-------------|----------------------|------------------|
| Left  🔊    | Speaker volume −/+   | Mute speakers    |
| Right 🎤    | Microphone volume −/+| Mute microphone  |

Each action shows a single notification like `🎤 Microphone 75%` or
`🔊 Speakers MUTED`, with a progress bar.

---

## Quick start

Requirements: Linux, [Rust/cargo](https://rustup.rs) (to build the flashing
tool), PipeWire with `wpctl` (WirePlumber), and `notify-send`. Desktop shortcut
wiring is automated for **XFCE**; for GNOME/KDE see [Other desktops](#other-desktops).

```bash
git clone <this-repo> videyt-macropad-linux
cd videyt-macropad-linux
./install.sh
```

Then turn a knob. That's it.

`install.sh` is idempotent — re-run it anytime. It:

1. installs `ch57x-keyboard-tool` (via cargo) if missing,
2. installs the `macropad-audio` helper to `~/.local/bin` (override with `BIN_DIR=`),
3. binds the knob keysyms to that helper via XFCE keyboard shortcuts,
4. silences the panel's built-in volume popup so it doesn't duplicate ours,
5. uploads `macropad.yaml` to the device (asks for `sudo` — USB write needs root).

---

## How it works

Three moving parts:

**1. The device key map (`macropad.yaml`).**
Flashed with [`ch57x-keyboard-tool`](https://github.com/kriomant/ch57x-keyboard-tool).
The device can only emit standard HID codes — there is **no HID code for
"microphone volume"**. So instead of trying to send audio codes, each knob action
sends a **spare key** (`F13`–`F18`), and the desktop turns that key into an audio
command.

**2. The helper (`bin/macropad-audio`).**
A small script that runs one `wpctl` action on the default sink/source and then
pops a labelled notification:

```
macropad-audio mic-up      # microphone +5%
macropad-audio spk-mute    # toggle speaker mute
# …mic-down, mic-mute, spk-up, spk-down
```

It targets `@DEFAULT_AUDIO_SINK@` / `@DEFAULT_AUDIO_SOURCE@`, so it follows
whatever output/input you're currently using — no device names baked in.

**3. Desktop shortcuts.**
Each spare keysym is bound to a `macropad-audio` action. On XFCE this is
`xfce4-keyboard-shortcuts`; the same keysym→command mapping works on any WM.

```
knob        HID key   keysym          command
────────────────────────────────────────────────────────
mic  turn+  f13       XF86Tools       macropad-audio mic-up
mic  turn−  f14       XF86Launch5     macropad-audio mic-down
mic  press  f15       XF86Launch6     macropad-audio mic-mute
spk  press  f16       XF86Launch7     macropad-audio spk-mute
spk  turn−  f17       XF86Launch8     macropad-audio spk-down
spk  turn+  f18       XF86Launch9     macropad-audio spk-up
```

---

## The gotcha that cost an afternoon: `F20` is already "mute mic"

The obvious first attempt is to map the mic knob to `F19`/`F20`/`F21` and bind
those. It doesn't work — turning the knob just **toggles the microphone mute**
and the volume never moves.

Why: on a standard Linux/Xorg evdev keymap, the high function keys are **not**
plain function keys. Check yours:

```bash
xmodmap -pke | sed -n 'p' | grep -Ei 'F1[3-9]|F2[0-4]|Launch|AudioMic|Touchpad'
```

You'll typically find:

```
keycode 198 = XF86AudioMicMute      # this is "F20"
keycode 199 = XF86TouchpadToggle    # "F21"
keycode 200 = XF86TouchpadOn        # "F22"
…
```

So `F20` **is** the system "mute microphone" key — a global handler grabs it
before any custom shortcut runs. `F21`/`F22` are touchpad toggles; `F19`/`F24`
are often unmapped (no keysym, unbindable).

The fix is to use only the **spare, side-effect-free** keysyms — `XF86Tools` and
`XF86Launch5`–`XF86Launch9` (the `F13`–`F18` range) — which have no default
handler, and bind those. That's what this repo does.

> Simulating the key with `xdotool key F20` is misleading: it injects a keysym
> named `F20` at the X level, which hits your custom shortcut, while the physical
> key emits keycode 198 = `XF86AudioMicMute` and never reaches it. Test with the
> real hardware, or read the raw events with `evtest`.

---

## Customization

**Remap the 15 keys or the knobs:** edit `macropad.yaml` and re-run
`./install.sh` (or `sudo ch57x-keyboard-tool upload < macropad.yaml`).
List valid key names with `ch57x-keyboard-tool show-keys`.

**Change the volume step or notification look:** edit `bin/macropad-audio`
(the `5%+` / `5%-` steps and the `notify-send` line) and re-run `./install.sh`.

**The device can't be read back** — `ch57x-keyboard-tool` only writes. Every
upload replaces the whole map. Keep `macropad.yaml` as your source of truth.

---

## Other desktops

The device flashing and the `macropad-audio` helper are desktop-agnostic. Only
step 3 (binding keysyms) and step 4 (silencing the panel popup) are XFCE-specific.

- **GNOME/KDE/etc.:** bind each keysym in the table above to the matching
  `~/.local/bin/macropad-audio …` command using your desktop's keyboard settings,
  and disable your panel's own volume OSD if it duplicates the notification.
- **Wayland:** `wpctl` and `notify-send` work the same; use your compositor's
  shortcut mechanism (e.g. `hyprland` binds) instead of XFCE.

---

## Credits

Built on [`ch57x-keyboard-tool`](https://github.com/kriomant/ch57x-keyboard-tool)
by kriomant. Audio via PipeWire/WirePlumber (`wpctl`).
