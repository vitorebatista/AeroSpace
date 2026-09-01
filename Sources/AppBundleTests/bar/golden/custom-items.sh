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

sketchybar --add item aerospace.custom left
sketchybar --set aerospace.custom \
    icon=terminal \
    icon.font='SF Pro:Semibold:14.0' \
    script='/opt/homebrew/bin/my-status --oneline'
sketchybar --subscribe aerospace.custom front_app_switched system_woke

sketchybar --add item aerospace.custom.2 left
sketchybar --set aerospace.custom.2 \
    icon=terminal \
    icon.font='SF Pro:Semibold:14.0' \
    script='"$HOME/scripts/my status.sh" --json' \
    update_freq=15

# aerospace.custom.3: no script path set, not generated

# aerospace.not-a-catalog-item: no catalog entry, not generated

sketchybar --add bracket aerospace.bracket.left.escape-hatch aerospace.custom aerospace.custom.2
sketchybar --set aerospace.bracket.left.escape-hatch \
    background.drawing=on \
    background.border_color=0xff717ebb \
    background.border_width=1 \
    background.corner_radius=10 \
    background.height=26

sketchybar --update
