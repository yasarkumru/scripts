#!/usr/bin/env bash
# Logs processes exceeding threshold network usage to ~/nethogs.log.
# Uses ss (via cntlm port) if cntlm is running, nethogs otherwise.


THRESHOLD_KB=1024
LOG_FILE="$HOME/nethogs.log"
INTERVAL=1
CNTLM_PORT=3128

rm -f "$LOG_FILE"

run_ss_mode() {
    declare -A prev_sent prev_recv
    local prev_hs_rx=0 prev_hs_tx=0

    get_hotspot_iface() {
        ip -4 addr show | awk '
            /^[0-9]+: / { match($0, /^[0-9]+: ([^:@]+)/, m); iface = m[1] }
            /inet 10\.42\.0\.1\// { print iface; exit }
        '
    }

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
                    up_mb=$(awk "BEGIN {printf \"%.2f\", $ds / $INTERVAL / 1048576}")
                    down_mb=$(awk "BEGIN {printf \"%.2f\", $dr / $INTERVAL / 1048576}")
                    printf '%s\t%s\tup: %s MB/s\tdown: %s MB/s\n' \
                        "$(date '+%Y-%m-%d %H:%M:%S')" "$name" "$up_mb" "$down_mb" \
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

        # Hotspot (phone) tracking
        local hs_iface hs_rx hs_tx
        hs_iface=$(get_hotspot_iface)
        if [[ -n "$hs_iface" ]]; then
            hs_rx=$(< /sys/class/net/$hs_iface/statistics/rx_bytes)
            hs_tx=$(< /sys/class/net/$hs_iface/statistics/tx_bytes)
            if [[ $prev_hs_rx -gt 0 ]]; then
                local drx=$(( hs_rx - prev_hs_rx ))
                local dtx=$(( hs_tx - prev_hs_tx ))
                (( drx < 0 )) && drx=0
                (( dtx < 0 )) && dtx=0
                local hs_up_kb=$(( drx / INTERVAL / 1024 ))
                local hs_down_kb=$(( dtx / INTERVAL / 1024 ))
                if (( hs_up_kb > THRESHOLD_KB || hs_down_kb > THRESHOLD_KB )); then
                    up_mb=$(awk "BEGIN {printf \"%.2f\", $drx / $INTERVAL / 1048576}")
                    down_mb=$(awk "BEGIN {printf \"%.2f\", $dtx / $INTERVAL / 1048576}")
                    printf '%s\tphone (hotspot)\tup: %s MB/s\tdown: %s MB/s\n' \
                        "$(date '+%Y-%m-%d %H:%M:%S')" "$up_mb" "$down_mb" \
                        >> "$LOG_FILE"
                fi
            fi
            prev_hs_rx=$hs_rx
            prev_hs_tx=$hs_tx
        else
            prev_hs_rx=0
            prev_hs_tx=0
        fi

        sleep "$INTERVAL"
    done
}

run_nethogs_mode() {
    local NETHOGS
    NETHOGS=$(command -v nethogs 2>/dev/null || echo /home/linuxbrew/.linuxbrew/sbin/nethogs)
    [[ ! -x "$NETHOGS" ]] && exit 0

    while true; do
        sudo "$NETHOGS" -t -d "$INTERVAL" 2>/dev/null | while IFS=$'\t' read -r program sent recv; do
            [[ "$program" == "Refreshing:" || -z "$program" || "$program" == Unknown* ]] && continue
            sent_kb=${sent%%.*}
            recv_kb=${recv%%.*}
            [[ "$sent_kb" =~ ^[0-9]+$ && "$recv_kb" =~ ^[0-9]+$ ]] || continue
            if (( sent_kb > THRESHOLD_KB || recv_kb > THRESHOLD_KB )); then
                up_mb=$(awk "BEGIN {printf \"%.2f\", $sent / 1024}")
                down_mb=$(awk "BEGIN {printf \"%.2f\", $recv / 1024}")
                printf '%s\t%s\tup: %s MB/s\tdown: %s MB/s\n' \
                    "$(date '+%Y-%m-%d %H:%M:%S')" "$program" "$up_mb" "$down_mb" \
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
