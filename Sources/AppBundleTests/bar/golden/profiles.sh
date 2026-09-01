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

sketchybar --add item aerospace.workspaces left
sketchybar --set aerospace.workspaces \
    icon=square.grid.2x2 \
    icon.font='SF Pro:Semibold:14.0' \
    icon.color=0xff717ebb \
    update_freq=1 \
    script='sketchybar --set $NAME label="$(/opt/homebrew/bin/aerospace-edge list-workspaces --monitor focused --empty no --format '\''%{workspace}|%{workspace-is-focused}'\'' | while IFS='\''|'\'' read -r w f; do if [ "$f" = true ]; then printf '\''[%s]'\'' "$w"; else printf '\''%s'\'' "$w"; fi; printf '\'' '\''; done | sed '\''s/ $//'\'')"' \
    drawing=on
sketchybar --subscribe aerospace.workspaces front_app_switched space_change display_change

sketchybar --add item aerospace.cpu right
sketchybar --set aerospace.cpu \
    icon=cpu \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=5 \
    script='u=$(ps -A -o %cpu= | awk -v n="$(sysctl -n hw.ncpu)" '\''{s+=$1} END {printf "%d", s/n}'\''); if [ "$u" -gt 85 ]; then c=0xffff5f5f; else c=0xffeeeeee; fi; sketchybar --set $NAME label="$u%" icon.color=$c label.color=$c' \
    drawing=on

sketchybar --add item aerospace.weather right
sketchybar --set aerospace.weather \
    icon=cloud.sun \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=900 \
    script='sketchybar --set $NAME label="$(curl -sf --max-time 10 '\''https://wttr.in/?format=%t&m'\'' | tr -d '\''+ '\'')"' \
    drawing=on

sketchybar --add bracket aerospace.bracket.right.system aerospace.cpu aerospace.weather
sketchybar --set aerospace.bracket.right.system \
    background.drawing=on \
    background.border_color=0xff717ebb \
    background.border_width=1 \
    background.corner_radius=10 \
    background.height=26

sketchybar --update
