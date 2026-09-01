#!/bin/sh
# Managed by AeroSpace-edge. Generated from ~/.config/aerospace/bar.toml.
# Edits to this file are overwritten on the next save.
# aerospace-edge-generated: 1

sketchybar --bar \
    position=top \
    height=40 \
    margin=0 \
    y_offset=0 \
    corner_radius=0 \
    border_width=2 \
    padding_left=4 \
    padding_right=4 \
    color=0xff1e1e2e \
    border_color=0xff313244

sketchybar --default \
    icon.font='SF Pro:Semibold:14.0' \
    icon.color=0xffcdd6f4 \
    icon.padding_left=6 \
    icon.padding_right=4 \
    label.font='SF Pro:Semibold:13.0' \
    label.color=0xffcdd6f4 \
    label.padding_left=0 \
    label.padding_right=6 \
    background.drawing=off \
    background.corner_radius=6 \
    background.height=24 \
    popup.background.color=0xff181825 \
    popup.background.border_color=0xff45475a \
    popup.background.border_width=1 \
    popup.background.corner_radius=6

sketchybar --add item aerospace.workspaces left
sketchybar --set aerospace.workspaces \
    icon=square.grid.2x2 \
    icon.font='SF Pro:Semibold:14.0' \
    icon.color=0xfff9e2af \
    update_freq=1 \
    script='sketchybar --set $NAME label="$(/opt/homebrew/bin/aerospace-edge list-workspaces --monitor all --format '\''%{workspace}|%{workspace-is-focused}'\'' | while IFS='\''|'\'' read -r w f; do if [ "$f" = true ]; then printf '\''[%s]'\'' "$w"; else printf '\''%s'\'' "$w"; fi; /opt/homebrew/bin/aerospace-edge list-windows --workspace "$w" --format '\''%{app-name}'\'' | sort -u | while IFS= read -r a; do /opt/homebrew/share/sketchybar-app-font/icon_map.sh "$a"; done; printf '\'' '\''; done | sed '\''s/ $//'\'')"'
sketchybar --subscribe aerospace.workspaces front_app_switched space_change display_change

sketchybar --add item aerospace.mode left
sketchybar --set aerospace.mode \
    icon=keyboard \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=1 \
    script='m=$(/opt/homebrew/bin/aerospace-edge list-modes --current); sketchybar --set $NAME drawing=on label="$(printf '\''-- %s --'\'' "$m")"'

sketchybar --add item aerospace.floats left
sketchybar --set aerospace.floats \
    icon=macwindow.on.rectangle \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=2 \
    script='sketchybar --set $NAME drawing=on label.drawing=off' \
    click_script='id=$(/opt/homebrew/bin/aerospace-edge list-windows --workspace focused --format '\''%{window-id}|%{window-parent-container-layout}'\'' | grep '\''|floating$'\'' | head -n1 | cut -d'\''|'\'' -f1); [ -n "$id" ] && /opt/homebrew/bin/aerospace-edge focus --window-id "$id"'
sketchybar --subscribe aerospace.floats front_app_switched space_change

sketchybar --add item aerospace.front-app center
sketchybar --set aerospace.front-app \
    icon=macwindow \
    icon.font='SF Pro:Semibold:14.0' \
    icon.drawing=off \
    script='sketchybar --set $NAME label="$(printf '\''%.24s'\'' "$INFO")"'
sketchybar --subscribe aerospace.front-app front_app_switched

sketchybar --add graph aerospace.cpu right 40
sketchybar --set aerospace.cpu \
    icon=cpu \
    icon.font='SF Pro:Semibold:14.0' \
    graph.color=0xfff38ba8 \
    update_freq=2 \
    script='u=$(ps -A -o %cpu= | awk -v n="$(sysctl -n hw.ncpu)" '\''{s+=$1} END {printf "%d", s/n}'\''); if [ "$u" -gt 85 ]; then c=0xffff5f5f; else c=0xffcdd6f4; fi; sketchybar --set $NAME label="$u%" icon.color=$c label.color=$c; sketchybar --push $NAME "$(awk -v u="$u" '\''BEGIN {printf "%.2f", u/100}'\'')"'

sketchybar --add item aerospace.network right
sketchybar --set aerospace.network \
    icon=wifi \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=5 \
    script='s=$(networksetup -getairportnetwork en0 2>/dev/null | sed -n '\''s/^Current Wi-Fi Network: //p'\''); [ -z "$s" ] && s=offline; a=$(netstat -ib | awk '\''$1=="en0" && /Link/ {print $7"|"$10; exit}'\''); sleep 1; b=$(netstat -ib | awk '\''$1=="en0" && /Link/ {print $7"|"$10; exit}'\''); rx=$(( (${b%|*} - ${a%|*}) / 1024 )); tx=$(( (${b#*|} - ${a#*|}) / 1024 )); sketchybar --set $NAME label="$s v${rx}K ^${tx}K"'

sketchybar --add item aerospace.weather right
sketchybar --set aerospace.weather \
    icon=cloud.sun \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=900 \
    script='sketchybar --set $NAME label="$(curl -sf --max-time 10 '\''https://wttr.in/New%20York,US?format=%t&u'\'' | tr -d '\''+ '\'')"'

sketchybar --add item aerospace.battery right
sketchybar --set aerospace.battery \
    icon=battery.100 \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=120 \
    script='p=$(pmset -g batt | grep -Eo '\''[0-9]+%'\'' | head -n1 | tr -d '\''%'\''); [ -z "$p" ] && p=0; if [ "$p" -lt 20 ]; then c=0xffff5f5f; else c=0xffcdd6f4; fi; sketchybar --set $NAME icon.color=$c label.color=$c label.drawing=off'
sketchybar --subscribe aerospace.battery power_source_change system_woke

sketchybar --add item aerospace.secure-input right
sketchybar --set aerospace.secure-input \
    icon=lock.shield \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=2 \
    script='pid=$(ioreg -l -w 0 | sed -n '\''s/.*"kCGSSessionSecureInputPID"=\([0-9]*\).*/\1/p'\'' | head -n1); if [ -n "$pid" ] && [ "$pid" != 0 ]; then n=$(ps -p "$pid" -o comm= 2>/dev/null | sed '\''s|.*/||'\''); sketchybar --set $NAME drawing=on label="$n"; else sketchybar --set $NAME drawing=on label.drawing=off; fi'

sketchybar --add bracket aerospace.bracket.left.aerospace aerospace.workspaces aerospace.mode aerospace.floats
sketchybar --set aerospace.bracket.left.aerospace \
    background.drawing=on \
    background.border_color=0xfff38ba8 \
    background.border_width=2 \
    background.corner_radius=0 \
    background.height=26

sketchybar --add bracket aerospace.bracket.right.system aerospace.cpu aerospace.network aerospace.weather aerospace.battery
sketchybar --set aerospace.bracket.right.system \
    background.drawing=on \
    background.border_color=0xfff38ba8 \
    background.border_width=2 \
    background.corner_radius=0 \
    background.height=26

sketchybar --update
