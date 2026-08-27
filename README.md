# videyt mini macropad on Linux — speaker + microphone knobs

Turn a cheap "Mini Keyboard" macropad (the ones whose manual only ships a
**Windows** app from `videyt.com`) into a tidy **speaker + microphone controller
on Linux** — with clean, labelled desktop notifications and **no background
daemon**.

This is the pad sold under a dozen brands: **12 keys + 2 rotary knobs**, showing
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

## Hardware

Any pad that enumerates as USB `1189:8840` works. This is the exact unit I used:

- 🛒 **[Mini macropad — 12 keys + 2 knobs](https://amzn.to/3SW6Hrf)**

<sub>That's an Amazon affiliate link — buying through it supports this project at no extra cost to you.</sub>

---

## Quick start

Requirements: Linux, [Rust/cargo](https://rustup.rs) (to build the flashing
tool), PipeWire with `wpctl` (WirePlumber), `notify-send`, and `xdotool` (for the
agent macros; X11/Xwayland). Desktop shortcut wiring is automated for **XFCE**;
for GNOME/KDE see [Other desktops](#other-desktops).

```bash
git clone <this-repo> videyt-macropad-linux
cd videyt-macropad-linux
./install.sh
```

Then turn a knob. That's it.

`install.sh` is idempotent — re-run it anytime. It:

1. installs `ch57x-keyboard-tool` (via cargo) if missing,
2. installs the `macropad-audio` and `macropad-say` helpers to `~/.local/bin` (override with `BIN_DIR=`),
3. binds the knob keysyms and the agent-macro keysyms to those helpers via XFCE keyboard shortcuts,
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
xmodmap -pke | sed -n 'p' | grep -Ei 'F1[3-9]|F2[0-4]|Launch|AudioMic|Touchpad|Props'
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

## The 12 keys: dictate, paste, send — and one-press agent macros

The pad has 12 keys (4 rows × 3 columns). This repo's `macropad.yaml` assigns
rows 1, 2 and 4, plus the first key of row 3; the other two row-3 keys are still
free placeholders.

- **Row 1 — dictate → paste → send:** a push-to-talk key (for a hold-to-talk
  speech-to-text), `Ctrl+Shift+V` (paste), and `Enter` (send).
- **Rows 2 and 3 — agent macros:** four keys that type the phrases you send
  coding agents all day. `install.sh` binds them via `bin/macropad-say`:

```
key             keysym               types
──────────────────────────────────────────────────────────────
row 2 left      XF86TouchpadToggle   go ahead, continue
row 2 middle    XF86TouchpadOn       merge the pull request, please
row 2 right     XF86TouchpadOff      stop
row 3 left      SunProps             one more round, please
```

Row 2's three keysyms are touchpad keys, inert only on a machine without a
touchpad — `install.sh` skips exactly those three when it detects one, and binds
the rest. `SunProps` is the fourth because the `F13`–`F24` range was already
spent: `F13`–`F18` drive the knobs, `F20` is `XF86AudioMicMute` (see the gotcha
above), and `F19`/`F24` carry no keysym at all, so nothing can bind them. It is
reached with the raw HID code `<118>`; Linux maps that usage to `KEY_PROPS`,
which Xorg presents as `SunProps`.

**All four keysyms are "free" on my machine, not on yours** — that is a fact
about a keymap and a desktop, not a property of the keys. Check before you trust
any of them, `SunProps` included:

```bash
xmodmap -pke | grep -i props                              # exists? (nothing = unbindable)
xfconf-query -c xfce4-keyboard-shortcuts -l | grep -i props   # already bound?
```

If a keysym is missing from the first command, nothing can bind it — pick
another. If it shows up in the second, it already does something else.

The device can only emit HID key codes, so it can't type a whole phrase. Instead
each key sends a **single spare keysym**, a desktop shortcut catches it, and
`macropad-say` types the phrase with `xdotool`. To change the wording, edit
`bin/macropad-say` and re-run `./install.sh` (the shortcut runs the *installed*
copy) — no device reflash needed.

> **Learn from my mistake — never use a modifier chord here.** My first version
> had each key send `Ctrl+Alt+Shift+<letter>`. Press it once and the modifiers
> latched **stuck** at the X level: from then on every keystroke was a chord,
> `F1` opened a browser, windows vanished, and the real keyboard's shortcuts
> died. A single plain keysym can't do that — the knobs use exactly this pattern
> and never misbehaved. Because this machine has no touchpad,
> `XF86TouchpadToggle`/`On`/`Off` are inert, unbound keysyms that make good macro
> triggers; on a laptop, pick your own spare keys for those three (`install.sh`
> skips them there, and binds the rest). Give `SunProps` the same scrutiny — it
> is unbound *here*, which is not a promise about your machine. Verify all four
> with the two commands above.
>
> One timing note: `macropad-say` sleeps 200 ms before typing, or the shortcut
> fires before the key settles and `xdotool` drops the first characters.

- **Row 4 — utility:** `Shift+PrintScreen` (selection screenshot), `Ctrl+V`
  (paste), and `Enter` (send) — handy on a keyboard without a dedicated
  `PrtScn` key. These rely on your desktop already binding those shortcuts.

**Decoding the key positions.** The firmware scrambles the physical layout — the
top-left key is **not** row 0, column 0 in `macropad.yaml`. Decode your unit by
flashing 12 distinct letters, pressing the keys in physical order, and noting
which letter each produces; the comment block at the top of `macropad.yaml` shows
the map for this unit.

---

## Customization

**Remap the 12 keys or the knobs:** edit `macropad.yaml` and re-run
`./install.sh` (or `sudo ch57x-keyboard-tool upload < macropad.yaml`).
List valid key names with `ch57x-keyboard-tool show-keys`.

**Change the volume step or notification look:** edit `bin/macropad-audio`
(the `5%+` / `5%-` steps and the `notify-send` line) and re-run `./install.sh`.

**Run the tests after touching `install.sh`:**

```bash
tests/touchpad-guard.test.sh
```

It stubs `xinput` and `xfconf-query` to check the macro-binding guard both ways —
with a touchpad only the three `XF86Touchpad*` keysyms are skipped, without one
all four bind — without writing to your real desktop configuration.

**The device can't be read back** — `ch57x-keyboard-tool` only writes. Every
upload replaces the whole map. Keep `macropad.yaml` as your source of truth.

---

## Other desktops

The device flashing and the `macropad-audio` helper are desktop-agnostic. Only
step 3 (binding keysyms) and step 4 (silencing the panel popup) are XFCE-specific.

- **GNOME/KDE/etc.:** bind each knob keysym in the table above to the matching
  `~/.local/bin/macropad-audio …` command, and the macro keysyms
  (`XF86TouchpadToggle`/`On`/`Off` and `SunProps`, or your own spare keys) to
  `~/.local/bin/macropad-say go|merge|stop|round`, using your desktop's keyboard
  settings. Disable your panel's own volume OSD if it duplicates the notification.
- **Wayland:** `wpctl` and `notify-send` work the same; use your compositor's
  shortcut mechanism (e.g. `hyprland` binds) instead of XFCE. Note that
  `macropad-say` uses `xdotool`, which only types into X11/Xwayland windows — for
  native Wayland apps, swap it for `wtype` or `ydotool`.

---

## Credits

Built on [`ch57x-keyboard-tool`](https://github.com/kriomant/ch57x-keyboard-tool)
by kriomant. Audio via PipeWire/WirePlumber (`wpctl`).
