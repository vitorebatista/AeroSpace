#!/bin/sh
# Managed by AeroSpace-edge. Generated from ~/.config/aerospace/bar.toml.
# Edits to this file are overwritten on the next save.
# aerospace-edge-generated: 1

sketchybar --bar \
    position=top \
    height=32 \
    margin=8 \
    y_offset=6 \
    corner_radius=10 \
    border_width=1 \
    padding_left=1 \
    padding_right=0 \
    color=0xb3202020 \
    border_color=0x35e2e2e3

sketchybar --default \
    icon.font='SF Pro:Semibold:14.0' \
    icon.color=0xffeeeeee \
    icon.padding_left=6 \
    icon.padding_right=4 \
    label.font='SF Pro:Semibold:13.0' \
    label.color=0xffeeeeee \
    label.padding_left=0 \
    label.padding_right=6 \
    background.drawing=off \
    background.corner_radius=6 \
    background.height=24 \
    popup.background.color=0xc02c2e34 \
    popup.background.border_color=0xff7f8490 \
    popup.background.border_width=1 \
    popup.background.corner_radius=6

sketchybar --add item aerospace.brightness right
sketchybar --set aerospace.brightness \
    icon=sun.max \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=5 \
    script='if [ "$SENDER" = mouse.scrolled ]; then b=$(/opt/homebrew/bin/brightness -l 2>/dev/null | awk '\''/brightness/ {printf "%d", $NF*100; exit}'\''); d=${SCROLL_DELTA%%.*}; [ -z "$b" ] && b=0; n=$b; if [ "$d" -gt 0 ] 2>/dev/null; then n=$((b + 5)); elif [ "$d" -lt 0 ] 2>/dev/null; then n=$((b - 5)); fi; [ "$n" -gt 100 ] && n=100; [ "$n" -lt 1 ] && n=1; /opt/homebrew/bin/brightness "$(awk -v n="$n" '\''BEGIN {printf "%.2f", n/100}'\'')"; fi; b=$(/opt/homebrew/bin/brightness -l 2>/dev/null | awk '\''/brightness/ {printf "%d", $NF*100; exit}'\''); sketchybar --set $NAME label="$b%"'
sketchybar --subscribe aerospace.brightness mouse.scrolled

sketchybar --add item aerospace.bluetooth right
sketchybar --set aerospace.bluetooth \
    icon=dot.radiowaves.right \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=5 \
    script='p=$(/opt/homebrew/bin/blueutil -p 2>/dev/null); if [ "$p" = 1 ]; then l=on; sketchybar --set $NAME drawing=on label="$l"; else sketchybar --set $NAME drawing=off; fi' \
    click_script='/opt/homebrew/bin/blueutil -p toggle'

sketchybar --add bracket aerospace.bracket.right.privileged aerospace.brightness aerospace.bluetooth
sketchybar --set aerospace.bracket.right.privileged \
    background.drawing=on \
    background.border_color=0xff717ebb \
    background.border_width=1 \
    background.corner_radius=10 \
    background.height=26

sketchybar --update
