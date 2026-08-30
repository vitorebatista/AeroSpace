---
title: subscribe
description: Subscribe to AeroSpace events and receive notifications via socket
section: 1
---

# aerospace-edge subscribe

Subscribe to AeroSpace events and receive notifications via socket

## Synopsis

```synopsis
aerospace-edge subscribe [-h|--help] [--all] [--no-send-initial] [<event>...]
```

## Description

This command connects to the AeroSpace server and receives real-time event notifications as JSON lines. The connection remains open until terminated (e.g., via Ctrl+C).

On connect, the current state is sent immediately (focus-changed with current window/workspace, mode-changed with current mode, etc.).

## Options

`-h`, `--help`

: Print help

`--all`

: Subscribe to all event types

`--no-send-initial`

: Do not send the initial state on connect

## Arguments

The following events can be subscribed to:

focus-changed

: Fired when window focus changes. Includes `windowId`, `workspace`.

focused-monitor-changed

: Fired when the focused monitor changes. Includes `workspace`, `monitorId`.

focused-workspace-changed

: Fired when the focused workspace changes. Includes `workspace`, `prevWorkspace`.

mode-changed

: Fired when the binding mode changes. Includes `mode`.

window-detected

: Fired when a new window is detected. Includes `windowId`, `workspace`, `appBundleId`, `appName`.

binding-triggered

: Fired when a keyboard binding is triggered. Includes `binding`, `mode`.

workspace-layout-changed

: Fired when the layout of a workspace’s root tiling container changes. Includes `workspace`, `layout`.

window-moved-to-workspace

: Fired when a window is moved to another workspace. Includes `windowId`, `workspace` (the destination), `prevWorkspace` (the source, may be null).

window-closed

: Fired when a window is closed. Includes `windowId`, `workspace`.

## Output Format

Events are output as JSON lines (one JSON object per line):

    {"_event":"focused-monitor-changed","monitorId":1,"workspace":"M"}
    {"_event":"focused-workspace-changed","prevWorkspace":"M","workspace":"M"}
    {"_event":"mode-changed","mode":"main"}
    {"_event":"focus-changed","windowId":28218,"workspace":"M"}
