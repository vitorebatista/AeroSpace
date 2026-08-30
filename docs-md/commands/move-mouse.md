---
title: move-mouse
description: Move mouse to the requested position
section: 1
---

# aerospace-edge move-mouse

Move mouse to the requested position

## Synopsis

```synopsis
aerospace-edge move-mouse [-h|--help] [--fail-if-noop] <mouse-position>
```

## Description

## Options

`-h`, `--help`

: Print help

`--fail-if-noop`

: Exit with non-zero exit code if mouse is already at the requested position. The flag is compatible only with `window-lazy-center` and `monitor-lazy-center` arguments.

## Arguments

`<mouse-position>`

: Position to move mouse to. Possible values:

  - `monitor-lazy-center`. Move mouse to the center of the focused monitor, **unless** it is already within the monitor boundaries.

  - `monitor-force-center`. Move mouse to the center of the focused monitor.

  - `window-lazy-center`. Move mouse to the center of the focused window, **unless** it is already within the window boundaries. Exit with non-zero code if no window is focused.

  - `window-force-center`. Move mouse to the center of the focused window. Exit with non-zero code if no window is focused.

## Examples

- Try to move mouse to the center of the window. If there is no window in focus, move mouse to the center of the monitor:  
  `aerospace-edge move-mouse window-lazy-center || aerospace-edge move-mouse monitor-lazy-center`

## Resources

**Project homepage:** <https://github.com/nikitabobko/AeroSpace>  
**Guide:** <https://vitorebatista.github.io/AeroSpace-edge/guide/>  

## BUGS

Bugs can be reported to <https://github.com/nikitabobko/AeroSpace/discussions/categories/potential-bugs>

Maintainers will move verified bugs to <https://github.com/nikitabobko/AeroSpace/issues>

## License

Copyright © 2023 Nikita Bobko  
Free use of this software is granted under the terms of the MIT License  
You can find the full text of AeroSpace license and its dependencies in the 'legal' directory of the distributed zip archive.

## AUTHOR

Nikita Bobko and contributors
