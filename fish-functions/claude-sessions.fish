function claude-sessions
    set selected (bash ~/scripts/claude-sessions.sh | fzf --prompt="Select session: " --height=40% --layout=reverse)
    if test -z "$selected"
        return
    end
    set uuid (echo $selected | awk '{print $3}')
    claude --resume $uuid
end
