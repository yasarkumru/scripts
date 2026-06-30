#!/usr/bin/env bash
# Logs processes exceeding threshold network usage to ~/nethogs.log.
# Uses ss (via cntlm port) if cntlm is running, nethogs otherwise.

THRESHOLD_KB=1024
LOG_FILE="$HOME/nethogs.log"
INTERVAL=3
CNTLM_PORT=3128

rm -f "$LOG_FILE"

run_ss_mode() {
    declare -A prev_sent prev_recv

    get_app_bytes() {
        ss -tipe state established dst :"$CNTLM_PORT" 2>/dev/null | awk '
            /users:/ {
                match($0, /users:\(\("([^"]+)"/, proc)
                pending = proc[1]
            }
            pending && /bytes_sent:/ {
                match($0, /bytes_sent:([0-9]+)/, bs)
                match($0, /bytes_received:([0-9]+)/, br)
                sent[pending] += bs[1]; recv[pending] += br[1]
                pending = ""
            }
            END { for (name in sent) print name, sent[name], recv[name] }
        '
    }

    while true; do
        declare -A curr_sent curr_recv
        while read -r name s r; do
            curr_sent[$name]=$s
            curr_recv[$name]=$r
        done < <(get_app_bytes)

        if [[ ${#prev_sent[@]} -gt 0 ]]; then
            for name in "${!curr_sent[@]}"; do
                ds=$(( curr_sent[$name] - ${prev_sent[$name]:-${curr_sent[$name]}} ))
                dr=$(( curr_recv[$name] - ${prev_recv[$name]:-${curr_recv[$name]}} ))
                (( ds < 0 )) && ds=0
                (( dr < 0 )) && dr=0
                up_kb=$(( ds / INTERVAL / 1024 ))
                down_kb=$(( dr / INTERVAL / 1024 ))
                if (( up_kb > THRESHOLD_KB || down_kb > THRESHOLD_KB )); then
                    printf '%s\t%s\tup: %d KB/s\tdown: %d KB/s\n' \
                        "$(date '+%Y-%m-%d %H:%M:%S')" "$name" "$up_kb" "$down_kb" \
                        >> "$LOG_FILE"
                fi
            done
        fi

        for key in "${!prev_sent[@]}"; do unset "prev_sent[$key]" "prev_recv[$key]"; done
        for key in "${!curr_sent[@]}"; do
            prev_sent[$key]=${curr_sent[$key]}
            prev_recv[$key]=${curr_recv[$key]}
            unset "curr_sent[$key]" "curr_recv[$key]"
        done

        sleep "$INTERVAL"
    done
}

run_nethogs_mode() {
    local NETHOGS
    NETHOGS=$(command -v nethogs 2>/dev/null || echo /home/linuxbrew/.linuxbrew/sbin/nethogs)
    [[ ! -x "$NETHOGS" ]] && exit 0

    while true; do
        "$NETHOGS" -t -d "$INTERVAL" 2>/dev/null | while IFS=$'\t' read -r program sent recv; do
            [[ "$program" == "Refreshing:" || -z "$program" || "$program" == Unknown* ]] && continue
            sent_kb=${sent%%.*}
            recv_kb=${recv%%.*}
            [[ "$sent_kb" =~ ^[0-9]+$ && "$recv_kb" =~ ^[0-9]+$ ]] || continue
            if (( sent_kb > THRESHOLD_KB || recv_kb > THRESHOLD_KB )); then
                printf '%s\t%s\tup: %s KB/s\tdown: %s KB/s\n' \
                    "$(date '+%Y-%m-%d %H:%M:%S')" "$program" "$sent" "$recv" \
                    >> "$LOG_FILE"
            fi
        done
        sleep 1
    done
}

if pgrep -x cntlm >/dev/null 2>&1; then
    run_ss_mode
else
    run_nethogs_mode
fi
