# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

A collection of bash scripts for a Fedora Silverblue/Kinoite (rpm-ostree) desktop running KDE Plasma. Scripts are auto-started at login via `autostart.sh`.

## How it works

`autostart.sh` is the entry point (registered as a login/autostart item in KDE). On each login it:
1. Force-syncs the repo with `git fetch` + `git reset --hard origin/main` (discards local changes to avoid merge conflicts)
2. Runs every `autostart/*.sh` script in the background (disowned, no output)

Any script placed in `autostart/` will automatically be picked up and run at the next login.

## Conventions

**notify-send usage** — All desktop notifications follow this pattern:
```bash
notify-send \
    --icon=<icon-name> \
    -a "<App Name>" \
    --hint=string:desktop-entry:<desktop-id> \
    "<Summary>" \
    "<Body>"
```
The `--hint=string:desktop-entry:` value groups notifications under a KDE app identity (e.g. `org.kde.dolphin`, `steam`, `kcm_networkmanagement`).

**Autostart scripts** — Scripts in `autostart/` typically run an infinite loop with `sleep` intervals (polling-based) or block on a stream (event-based like `iw event`). They should be self-contained and safe to run in the background with no terminal.

## Scripts overview

- `autostart.sh` — Entry point: syncs repo, launches all `autostart/*.sh`
- `autostart/check-staged-update.sh` — Polls `rpm-ostree status` hourly; notifies when a system update is staged
- `autostart/monitor-hotspot.sh` — Monitors Wi-Fi AP connect/disconnect events via `iw event`; resolves device IPs and hostnames
- `autostart/notify-shader-cached-game.sh` — Polls for Steam `fossilize_replay` processes every 5s; notifies with game name when shader compilation starts
- `autostart/organize-downloads-monthly.sh` — Moves last month's Downloads into `~/Downloads/history/YYYY-Month/` (runs once; exits immediately if already done)