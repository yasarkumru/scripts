# Claude Code Status Line Yapılandırması

Terminal altında görünen `tansel@fedora | ~/proje |  main | Sonnet 5 | ctx:73%` şeklindeki satırın kurulumu.

## Nerede

1. **`~/.claude/settings.json`** — `statusLine` anahtarı script'i çağırır:
   ```json
   "statusLine": {
     "type": "command",
     "command": "bash /home/tansel/.claude/statusline-command.sh"
   }
   ```
2. **`~/.claude/statusline-command.sh`** — asıl script (executable, `#!/usr/bin/env bash`).

## Nasıl çalışıyor

Claude Code, her status line güncellemesinde script'e **stdin üzerinden JSON** gönderir (`.workspace.current_dir`, `.model.display_name`, `.context_window.remaining_percentage` gibi alanlar içerir). Script bunu `jq` ile parse edip renkli bir satır üretir ve stdout'a yazar.

## Gösterilen segmentler (soldan sağa)

| Segment | Kaynak | Renk |
|---|---|---|
| `user@host` | `whoami` + `hostname -s` | cyan/bold |
| dizin (`~` kısaltmalı) | `.workspace.current_dir` / `.cwd` | mavi |
| git branch | `git symbolic-ref --short HEAD` (fallback: kısa commit hash) | yeşil |
| model adı | `.model.display_name` | magenta |
| context kalan % | `.context_window.remaining_percentage` | yeşil (>50%) / sarı (20-50%) / kırmızı (≤20%) |

Segmentler arasında ` | ` ile ayrılıyor; git branch yoksa veya model/context bilgisi boşsa o segment atlanıyor.

## Powerlevel10k ilhamı

Script'in kendisi yorum satırında da belirtildiği gibi zsh için kullanılan Powerlevel10k prompt'undan esinlenerek yazıldı — aynı segment mantığı (user@host, dizin, git, ek bilgi) Claude Code status line'ına uyarlandı.

## Değiştirmek istersen

Script'i direkt düzenle: `~/.claude/statusline-command.sh`. Yeni segment eklemek için `parts+=(...)` satırlarına benzer bir satır eklemen, mevcut alanları kaldırmak için ilgili bloğu silmen yeterli — `settings.json`'da değişiklik gerekmiyor.
