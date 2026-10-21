# Polonium Tiling Fixes for KDE Plasma (Wayland)

Apply these fixes to a second PC running KDE Plasma 6 on Wayland. The goal:
Windows-like autotiling with Polonium — side-by-side default split, drag window
to the bottom edge of a screen → horizontal split, and a fix for a Polonium bug
that silently ignores windows whose title is empty at creation time (this
affects JetBrains IDEs and other apps that set their caption after mapping).

## What's in this folder

- `polonium-patched/` — complete patched Polonium 1.2.1 KWin script, ready to install.
  The only changes vs. stock 1.2.1 are in `contents/code/main3.mjs` (see "The patch" below);
  `contents/ui/main.qml` imports `main3.mjs` instead of `main.mjs`.
- `README.md` — this file.

## Step 1 — Install the patched Polonium script

```bash
mkdir -p ~/.local/share/kwin/scripts
cp -r polonium-patched ~/.local/share/kwin/scripts/polonium
```

If Polonium 1.2.1 is already installed from the KDE Store, this OVERWRITES it
with the patched copy — that is intended.

If some older/different Polonium version is installed, remove it first:

```bash
kpackagetool6 -t KWin/Script -r polonium   # ignore "not installed" errors
cp -r polonium-patched ~/.local/share/kwin/scripts/polonium
```

## Step 2 — Disable conflicting tiling scripts (if present)

If kZones (or another tiling script) is enabled, disable it:

```bash
kwriteconfig6 --file kwinrc --group Plugins --key kzonesEnabled false
```

Check what's enabled: `kreadconfig6 --file kwinrc --group Plugins --key poloniumEnabled`

## Step 3 — KWin config keys

```bash
# Polonium behaviour
kwriteconfig6 --file kwinrc --group Script-polonium --key WindowDragPolicy 0        # 0 = Always show drag-to-tile zones
kwriteconfig6 --file kwinrc --group Script-polonium --key BTreeRotateLayout false    # keep Windows-like split direction
kwriteconfig6 --file kwinrc --group Script-polonium --key LogLevel 1                 # quiet logging (3 = debug)

# Disable KWin edge quick-tiling so it doesn't fight Polonium
# (top-edge maximize keeps working)
kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderTiling false

# Enable Polonium
kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled true
```

## Step 4 — Remove KWin's native custom [Tiling] groups (if present)

Native KWin tiling layouts conflict with Polonium. Check:

```bash
grep -c '^\[Tiling\]' ~/.config/kwinrc
```

If any exist, strip ALL `[Tiling]...` groups (backup first):

```bash
cp ~/.config/kwinrc /tmp/kwinrc-backup-before-tiling-removal
python3 - <<'EOF'
path = "/home/YOURUSER/.config/kwinrc"   # <-- adjust username
lines = open(path).read().splitlines(keepends=True)
out, skip = [], False
for line in lines:
    if line.startswith("[Tiling]"):
        skip = True
        continue
    if skip and line.startswith("["):
        skip = False
    if not skip:
        out.append(line)
open(path, "w").write("".join(out))
EOF
```

## Step 5 — Clean stale Polonium shortcut entries (if upgrading from old Polonium)

Old Polonium versions left stale entries in `~/.config/kglobalshortcutsrc`,
including `PoloniumRetileWindow` which conflicts with
`PoloniumToggleActiveTiling` on Meta+Shift+Space. Current 1.2.1 registers only
these names — delete any other `Polonium*` line in the `[kwin]` section:

```
PoloniumToggleActiveTiling, PoloniumSetEngine*, PoloniumActivate*,
PoloniumPlace*, PoloniumResize{Up,Down,Left,Right},
PoloniumToggleSettingsMenu, PoloniumCycleEngine
```

Then restart the shortcut daemon:

```bash
systemctl --user restart plasma-kglobalaccel.service
```

## Step 6 — Activate and reload

KWin caches script CODE in memory. Safe reload sequence (never call loadScript
alone — it does not run the script):

```bash
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript polonium
kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled false
qdbus-qt6 org.kde.KWin /KWin reconfigure
sleep 2
kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled true
qdbus-qt6 org.kde.KWin /KWin reconfigure
```

IMPORTANT: if the script was installed/patched while KWin was already running,
the reload may still serve the CACHED old code. If behaviour looks unchanged,
log out and back in once — that always loads the new code.

## Step 7 — Verify

1. `journalctl --user -b | grep "Welcome to Polonium"` — script is running.
2. Open two windows → they tile side by side (vertical root split).
3. Drag a window to the BOTTOM edge of a screen → it takes the bottom half
   (horizontal split). Drag to the left/right edge → side-by-side.
4. `Meta+Shift+Space` toggles tiling on the focused window.
5. JetBrains IDE test: open an IDE, then open a project — the MAIN window must
   tile and stay tiled. (See "JetBrains note".)

## The patch (what main3.mjs changes vs. stock Polonium)

Two changes; re-apply by hand if installing on top of a different Polonium build.

### 1. The empty-caption bug (the important one)

In the config class (search for `ignoreWindowClasses`), stock code does:

```js
ignoreWindowCaptions = "^" + commaRegex(ignoreWindowCaptions) + "$";  // "" becomes "^$"
this.ignoreWindowCaptions = new RegExp(ignoreWindowCaptions);
```

`/^$/` matches the EMPTY STRING, so any window whose caption is still empty at
the moment KWin fires `windowAdded` (JetBrains X11/Wayland windows, splash
screens, apps that title themselves later) fails the
`ignoreWindowCaptions.test(window.caption)` check inside `windowAdded` and is
silently never registered — it never tiles, and Meta+Shift+Space does nothing
on it. Fix: make empty settings produce a never-matching regex:

```js
const neverMatch = "(?!x)x";
this.ignoreWindowClasses = new RegExp(ignoreWindowClasses === "^$" ? neverMatch : ignoreWindowClasses);
this.ignoreWindowCaptions = new RegExp(ignoreWindowCaptions === "^$" ? neverMatch : ignoreWindowCaptions);
this.untileWindowClasses  = new RegExp(untileWindowClasses  === "^$" ? neverMatch : untileWindowClasses);
this.untileWindowCaptions = new RegExp(untileWindowCaptions === "^$" ? neverMatch : untileWindowCaptions);
```

### 2. Root split direction from drag direction

In the BTree `placeWindow` implementation, stock code is (main3.mjs lines ~596-603):

```js
if (node.window === null) {
  node.window = window;
  return;
}
```

Replace with (root split follows the drag direction — bottom edge → horizontal split):

```js
if (node.window === null) {
  node.window = window;
  return;
}
if (node.parent === null && node.window !== null && direction !== void 0) {
  node.layoutDirectionRoot = direction & 4 /* Vertical */ ? 2 /* Vertical */ : 1 /* Horizontal */;
}
```

### 3. Nearest-edge drop zones (optional, feel improvement)

Stock `directionFromPoint` (top of main3.mjs) returns the KWin Direction from
screen quadrants, which makes the bottom drop zone small. This version picks
the NEAREST EDGE instead, so the bottom zone covers the whole bottom half:

```js
function directionFromPoint(r, p) {
  const x = p.x - r.x;
  const y = p.y - r.y;
  const dLeft = x;
  const dRight = r.width - x;
  const dTop = y;
  const dBottom = r.height - y;
  const min = Math.min(dLeft, dRight, dTop, dBottom);
  if (min === dBottom) return 1 /* Down */ | 4 /* Vertical */;
  if (min === dTop) return 4 /* Vertical */;
  if (min === dRight) return 2 /* Right */;
  return 0 /* None */;
}
```

(The patched file in `polonium-patched/` already contains all three changes.)

## JetBrains note

- With the empty-caption fix applied, JetBrains IDEs 2026.x work fine on
  native Wayland (WLToolkit) — no vmoptions change needed.
- JetBrains separately has YouTrack JBR-10511 ("WLToolkit: KDE KWin tile
  assignment is lost shortly after the IDE main window is created"), which
  JetBrains closed as invalid — the real cause is the Polonium bug above.
- Fallback ONLY if problems persist: force X11 toolkit by adding
  `-Dawt.toolkit.name=XToolkit` to the IDE's user vmoptions file, e.g.
  `~/.config/JetBrains/<Product><Version>/idea64.vmoptions` (for distrobox
  containers, adjust the path to the container's config dir).

## Troubleshooting

- KWin crashes/restarts when changing scripts: check
  `journalctl --user -b | grep -i polonium`.
- Script edits appear to do nothing: KWin cached the old module — log out/in.
- Config keys (LogLevel etc.) are read once at script start; toggling the
  `[Plugins]` enable flag via reconfigure (sequence in Step 6) restarts the
  script and re-reads them.
