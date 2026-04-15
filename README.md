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