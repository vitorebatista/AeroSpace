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
    script='sketchybar --set $NAME label="$(/opt/homebrew/bin/aerospace-edge list-workspaces --monitor focused --empty no --format '\''%{workspace}|%{workspace-is-focused}'\'' | while IFS='\''|'\'' read -r w f; do if [ "$f" = true ]; then printf '\''[%s]'\'' "$w"; else printf '\''%s'\'' "$w"; fi; printf '\'' '\''; done | sed '\''s/ $//'\'')"'
sketchybar --subscribe aerospace.workspaces front_app_switched space_change display_change

sketchybar --add item aerospace.apple-menu left
sketchybar --set aerospace.apple-menu \
    icon=apple.logo \
    icon.font='SF Pro:Semibold:14.0' \
    click_script='osascript -e '\''tell application "System Events" to tell (first process whose frontmost is true) to click menu bar item 1 of menu bar 1'\''' \
    label.drawing=off

sketchybar --add item aerospace.clock right
sketchybar --set aerospace.clock \
    icon=clock \
    icon.font='SF Pro:Semibold:14.0' \
    update_freq=30 \
    script='sketchybar --set $NAME label="$(date +'\''%a %d %b %H:%M'\'')"'

sketchybar --add item aerospace.volume right
sketchybar --set aerospace.volume \
    icon=speaker.wave.2 \
    icon.font='SF Pro:Semibold:14.0' \
    script='case "$SENDER" in mouse.clicked) osascript -e '\''set volume output muted (not (output muted of (get volume settings)))'\'';; mouse.scrolled) v=$(osascript -e '\''output volume of (get volume settings)'\''); d=${SCROLL_DELTA%%.*}; [ -z "$v" ] && v=0; n=$v; if [ "$d" -gt 0 ] 2>/dev/null; then n=$((v + 5)); elif [ "$d" -lt 0 ] 2>/dev/null; then n=$((v - 5)); fi; [ "$n" -gt 100 ] && n=100; [ "$n" -lt 0 ] && n=0; osascript -e "set volume output volume $n";; esac; s=$(osascript -e '\''set s to (get volume settings)'\'' -e '\''(output volume of s as text) & "|" & (output muted of s as text)'\''); v=${s%|*}; m=${s#*|}; if [ "$m" = true ]; then i=speaker.slash; else i=speaker.wave.2; fi; sketchybar --set $NAME icon=$i label="$v%"'
sketchybar --subscribe aerospace.volume volume_change mouse.clicked mouse.scrolled

sketchybar --add item aerospace.custom right
sketchybar --set aerospace.custom \
    icon=terminal \
    icon.font='SF Pro:Semibold:14.0' \
    script='~/.config/sketchybar/plugins/vpn.sh' \
    update_freq=60

sketchybar --update
