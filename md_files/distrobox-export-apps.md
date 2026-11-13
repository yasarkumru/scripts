# Exporting Applications from a Distrobox

How to make an app installed inside a distrobox show up in the host's app menu and
taskbar (KDE Plasma, Wayland), plus the pitfalls hit along the way.

---

## 1. Basic export

`distrobox-export` must run **inside** the box. From the host:

```bash
distrobox enter <box> -- distrobox-export --app <app-name>
```

Example:

```bash
distrobox enter onder-hayrati -- distrobox-export --app brave-origin
```

- `<app-name>` = name of the `.desktop` file inside the box
  (`/usr/share/applications/<app-name>.desktop`), or the binary name.
- Result: `~/.local/share/applications/<box>-<app-name>.desktop` on the host.
- Its `Name=` gets the suffix ` (on <box>)`.
- Its `Exec=` becomes `/usr/bin/distrobox-enter -n <box> -- <original command>`.

> `distrobox export ...` (with a space) is **not** a valid subcommand — use
> `distrobox-export`. Running `distrobox-export` on the host fails with
> `/run/.containerenv: No such file or directory`.

### Export a binary (CLI tool) instead of a GUI app

```bash
distrobox enter <box> -- distrobox-export --bin /usr/bin/<tool> --export-path ~/.local/bin
```

---

## 2. Remove an export

```bash
distrobox enter <box> -- distrobox-export --app <app-name> --delete
```

(`--unexport` does not exist; the flag is `--delete`.)

Check nothing is left behind:

```bash
ls ~/.local/share/applications/ | grep -i <app-name>
```

---

## 3. Refresh the menu

```bash
kbuildsycoca6 --noincremental
```

If the taskbar still shows stale pins:

```bash
systemctl --user restart plasma-plasmashell.service
```

---

## 4. Taskbar icon / pinning problems (Wayland)

**Rule:** on Wayland, KDE matches a window to a launcher by the window's
**`app_id`**, and that has to equal the **`.desktop` file name** (without `.desktop`).
`StartupWMClass=` only matters on X11.

Symptoms when they don't match:
- generic or missing icon in the taskbar
- "Pin to Task Manager" missing from the right-click menu
- a pinned launcher opens the app as a **second, separate icon**

### Find the window's real app_id

```bash
cat > /tmp/dumpwin.js <<'EOF'
for (const w of workspace.windowList())
    console.info("WINDUMP " + w.resourceClass + " || " + w.caption);
EOF
busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript s /tmp/dumpwin.js
busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting start
journalctl --user -n 50 --no-pager | grep WINDUMP
```

`resourceClass` = app_id.

### Fix

1. Name the host launcher **exactly** `<app_id>.desktop`, e.g.
   `~/.local/share/applications/brave-origin.desktop`.
2. For Chromium-based browsers you can force the app_id with `--class=<app_id>`.
   Keep it consistent with the file name.
3. Keep **only one** launcher for the app; delete the auto-generated
   `<box>-<app>.desktop` files to avoid duplicates.
4. `Name=` is only the label, so you can freely set it to e.g.
   `Brave Origin (on onder-hayrati)`.

### Icon

If the icon inside the box isn't visible on the host, copy it out:

```bash
mkdir -p ~/.local/share/icons/hicolor/256x256/apps
podman cp <box>:/opt/brave.com/brave-origin/product_logo_256.png \
  ~/.local/share/icons/hicolor/256x256/apps/brave.png
```

Then set `Icon=brave` in the `.desktop` file.

### Example launcher (final working version)

```ini
[Desktop Entry]
Type=Application
Name=Brave Origin (on onder-hayrati)
GenericName=Web Browser
Exec=/usr/bin/distrobox-enter -n onder-hayrati -e /usr/bin/brave-origin %U
Terminal=false
Icon=brave
StartupWMClass=brave-origin
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
```

---

## 5. Audio from a box app (host = PipeWire)

The host runs PipeWire with `pipewire-pulse`, which exposes a Pulse socket that
distrobox already bind-mounts. If the app is silent:

```bash
# inside the box
sudo apt install -y libpulse0 pulseaudio-utils
PULSE_SERVER=unix:/run/user/1000/pulse/native pactl info   # should print "PulseAudio (on PipeWire ...)"
```

Then make sure the app gets this env on every launch (see §6.4 on why to put it in
the wrapper):

```bash
export PULSE_SERVER="${PULSE_SERVER:-unix:/run/user/1000/pulse/native}"
```

---

## 6. Gotchas

1. **`distrobox enter -e` skips login env.** It runs non-login, so
   `/etc/profile.d/*` and `/etc/environment` are **not** loaded. Anything the app
   needs (env vars, flags) must go in the launch command or a wrapper script.
2. **Package upgrades overwrite patched files.** Anything under `/opt/...` or
   `/usr/bin/...` that belongs to a package gets reset on upgrade. Check:
   `dpkg -S <path>` (owned = will be overwritten). Put customisations in **your own
   wrapper script** that no package owns, and point the `.desktop` `Exec=` at it.
3. **Several launchers = several identities.** Old exports from other boxes, renamed
   files and stale pins each count as a different app. Clean them up.
4. **Wrapper over env.** A small wrapper script inside the box is the most reliable
   place for flags and env vars, because every launch path (menu, taskbar, terminal)
   runs through it.

---

## Extra: Proxy setup for a box

### A. Set a proxy for the whole box (new boxes)

Pass the proxy env when creating the box, so it ends up in the container config:

```bash
distrobox create -n <box> -i ubuntu:24.04 \
  --additional-flags "--env http_proxy=http://<PROXY_HOST>:<PORT> \
                      --env https_proxy=http://<PROXY_HOST>:<PORT> \
                      --env HTTP_PROXY=http://<PROXY_HOST>:<PORT> \
                      --env HTTPS_PROXY=http://<PROXY_HOST>:<PORT> \
                      --env no_proxy=localhost,127.0.0.1,10.,192.168. \
                      --env NO_PROXY=localhost,127.0.0.1,10.,192.168."
```

The container's env can't be changed after creation without recreating the box
(or editing podman's DB directly, which is risky; back it up first:
`~/.local/share/containers/storage/db.sql`).

### B. Inside the box

`/etc/apt/apt.conf.d/01proxy`:
```
Acquire::http::Proxy "http://<PROXY_HOST>:<PORT>";
Acquire::https::Proxy "http://<PROXY_HOST>:<PORT>";
```

`/etc/profile.d/proxy.sh` (login shells) and `/etc/environment` (PAM sessions):
```sh
export http_proxy=http://<PROXY_HOST>:<PORT>
export https_proxy=http://<PROXY_HOST>:<PORT>
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy
export no_proxy=localhost,127.0.0.1,10.,192.168.
export NO_PROXY=$no_proxy
```

Keep the proxy vars through `sudo` (`/etc/sudoers.d/proxy`):
```
Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
```

### C. Ubuntu image quirks behind the corporate proxy

- **Use HTTPS apt mirrors.** The upstream proxy mishandles some plain-HTTP package
  downloads (they hang). In `/etc/apt/sources.list.d/ubuntu.sources`, use
  `https://archive.ubuntu.com/ubuntu/` and `https://security.ubuntu.com/ubuntu/`.
- **Trust the host CAs** if TLS fails: copy the host bundle into the box
  (`/etc/ssl/certs/ca-certificates.crt`).
- **Disable `docker-clean`.** The ubuntu image's
  `/etc/apt/apt.conf.d/docker-clean` deletes downloaded `.deb`s after every apt
  run, so a slow/interrupted first init re-downloads everything forever:
  ```bash
  sudo mv /etc/apt/apt.conf.d/docker-clean /etc/apt/docker-clean.off
  ```

All of B and C is automated for new boxes by the init hook in
`~/.config/distrobox/distrobox.conf`:
```
container_init_hook="~/.config/distrobox/proxy-setup.sh"
```

### D. Proxy for an exported GUI app (e.g. a browser)

Because exported apps start via `distrobox enter -e` (non-login, see §6.1), the
proxy env from B may not reach them. Pin it in the **wrapper** instead. For
Chromium/Brave:

`/usr/bin/brave-origin` (own script, not package-owned):
```bash
#!/bin/bash
export PULSE_SERVER="${PULSE_SERVER:-unix:/run/user/1000/pulse/native}"
# ... rest of the original wrapper ...
"$HERE/brave" --proxy-server=http://<PROXY_HOST>:<PORT> --class=brave-origin "$@" || true
```

Verify the running process really has it:

```bash
P=$(pgrep -f '^/opt/brave.com/brave-origin/brave$|^/opt/brave.com/brave-origin/brave --proxy' | head -1)
tr '\0' '\n' < /proc/$P/cmdline
```

### E. Testing a proxy from the host

```bash
curl -x http://<PROXY_HOST>:<PORT> -s -o /dev/null \
     -w "%{http_code} %{time_total}s\n" https://www.youtube.com/
```

If a remote cntlm proxy refuses connections from other machines, it needs
`Gateway yes` (and your IP in `Allow`) in its `/etc/cntlm.conf`.
