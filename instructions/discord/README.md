# Discord Bypass

Launches Vesktop through SpoofDPI to bypass DPI-based blocking.

## Setup

```bash
# 1. Install Vesktop
flatpak install flathub dev.vencord.Vesktop

# 2. Install SpoofDPI
brew install spoofdpi

# 3. Allow spoofdpi to run without password via sudo
echo 'yasar ALL=(ALL) NOPASSWD: /home/linuxbrew/.linuxbrew/bin/spoofdpi' | sudo tee /etc/sudoers.d/spoofdpi

# 4. Make the script executable
chmod +x /var/home/yasar/scripts/discord/discord-bypass

# 5. Install the app launcher shortcut
cp /var/home/yasar/scripts/discord/discord-bypass.desktop ~/.local/share/applications/
```
