# Scripts

Personal automation scripts for Aurora Linux (immutable Fedora/KDE).

## Setup on a New Machine

### 1. Autostart

`autostart.sh` fetches the latest scripts from the remote repo and launches everything in `autostart/` in the background. It should be triggered at login via a KDE autostart entry.

```bash
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/scripts-autostart.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=scripts-autostart
Exec=/home/yasar/scripts/autostart.sh
X-KDE-AutostartScript=true
EOF
```

To stop all running autostart scripts:

```bash
bash ~/scripts/kill-autostart.sh
```

---

### 2. Claude Sessions (fish function)

`claude-sessions` lets you browse and resume previous Claude Code sessions interactively using fzf.

**Requirements:** `fzf` must be installed.

```bash
# Install fzf if missing
brew install fzf
```

Create the symlink so fish picks up the function:

```bash
mkdir -p ~/.config/fish/functions
ln -s ~/scripts/fish-functions/claude-sessions.fish ~/.config/fish/functions/claude-sessions.fish
```

Then open a new fish shell and run:

```bash
claude-sessions
```

Use arrow keys to select a session, Enter to resume it, Esc to cancel.
