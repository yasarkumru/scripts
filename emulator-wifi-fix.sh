#!/bin/bash
# Keeps the Pixel Tablet emulator (WiFi-only, no cellular) connected to
# the emulator's AndroidWifi AP. Quick boots restore the saved snapshot,
# this heals cold boots / reboots where WiFi doesn't auto-rejoin.
ADB="$HOME/Distrobox/android-dev/Android/Sdk/platform-tools/adb"
while true; do
  for s in $("$ADB" devices -l 2>/dev/null | awk '/model:Pixel_Tablet[[:space:]]/ {print $1}'); do
    booted=$("$ADB" -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    if [ "$booted" = "1" ]; then
      if ! "$ADB" -s "$s" shell ip route 2>/dev/null | grep -q '10.0.2.0/24'; then
        "$ADB" -s "$s" shell svc wifi enable >/dev/null 2>&1
        sleep 3
        "$ADB" -s "$s" shell cmd wifi connect-network AndroidWifi open >/dev/null 2>&1
      fi
    fi
  done
  sleep 30
done
