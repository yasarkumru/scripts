#!/usr/bin/env bash
# Claude Code statusLine command — inspired by Powerlevel10k p10k config
# Segments: user@host | dir | git branch | model | context %

input=$(cat)

user=$(whoami)
host=$(hostname -s)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)

# Shorten home directory to ~
home_dir="$HOME"
short_cwd="${cwd/#$home_dir/\~}"

# Git branch (skip optional locks)
git_branch=""
if git -C "$cwd" rev-parse --git-dir -q 2>/dev/null | grep -q .; then
    git_branch=$(git -C "$cwd" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" -c gc.auto=0 rev-parse --short HEAD 2>/dev/null)
fi

model=$(echo "$input" | jq -r '.model.display_name // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# ANSI colors (will be dimmed by Claude Code terminal)
BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
RESET="\033[0m"

# Build status line
parts=()

# user@host
parts+=("$(printf "${CYAN}${BOLD}%s@%s${RESET}" "$user" "$host")")

# directory
parts+=("$(printf "${BLUE}%s${RESET}" "$short_cwd")")

# git branch
if [ -n "$git_branch" ]; then
    parts+=("$(printf "${GREEN} %s${RESET}" "$git_branch")")
fi

# model
if [ -n "$model" ]; then
    parts+=("$(printf "${MAGENTA}%s${RESET}" "$model")")
fi

# context remaining
if [ -n "$remaining" ]; then
    remaining_int=$(printf "%.0f" "$remaining")
    if [ "$remaining_int" -le 20 ]; then
        ctx_color="\033[31m"  # red when low
    elif [ "$remaining_int" -le 50 ]; then
        ctx_color="${YELLOW}"
    else
        ctx_color="${GREEN}"
    fi
    parts+=("$(printf "${ctx_color}ctx:%d%%${RESET}" "$remaining_int")")
fi

# Join parts with separator
sep="$(printf "${RESET} | ")"
result=""
for part in "${parts[@]}"; do
    if [ -z "$result" ]; then
        result="$part"
    else
        result="${result}${sep}${part}"
    fi
done

printf "%b\n" "$result"
