#!/bin/bash
# List Claude Code sessions with timestamp and first message

PROJECTS_DIR="$HOME/.claude/projects"

for f in "$PROJECTS_DIR"/**/*.jsonl; do
  uuid=$(basename "$f" .jsonl)
  project=$(basename "$(dirname "$f")")

  read -r ts msg <<< "$(python3 - "$f" <<'EOF'
import json, sys

lines = open(sys.argv[1]).readlines()
msgs = []
for l in lines:
    l = l.strip()
    if not l:
        continue
    try:
        msgs.append(json.loads(l))
    except Exception:
        pass

first = [m for m in msgs if m.get('type') == 'user']
if not first:
    print("? ?")
    sys.exit()

m = first[0]
ts = m.get('timestamp', '?')[:16]
c = m['message']['content']
if isinstance(c, str):
    text = c
elif isinstance(c, list):
    text = next((x.get('text', '') for x in c if isinstance(x, dict) and x.get('type') == 'text'), '')
else:
    text = '?'

print(ts + '\t' + text[:100].replace('\n', ' '))
EOF
  )"

  echo "$ts | $uuid | $project | $msg"
done | sort -r
