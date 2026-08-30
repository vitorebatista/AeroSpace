---
title: list-apps
description: Print the list of running applications that appears in the Dock and may have a user interface
section: 1
---

# aerospace-edge list-apps

Print the list of running applications that appears in the Dock and may have a user interface

## Synopsis

```synopsis
aerospace-edge list-apps [-h|--help] [--macos-native-hidden [no]] [--format <output-format>] [--count] [--json]
```

## Description

The command is useful to inspect list of applications to compose filter for [on-window-detected callback](../guide.md#on-window-detected-callback)

## Options

`-h`, `--help`

: Print help

--macos-native-hidden [no]

: Filter results to only print hidden applications. `[no]` inverts the condition

`--format <output-format>`

: Specify output format. See "Output Format" section for more details. Incompatible with `--count`

`--count`

: Output only the number of apps. Incompatible with: `--format`, `--json`

`--json`

: Output in JSON format. Can be used in combination with `--format` to specify which data to include into the json. Incompatible with `--count`

## Output Format

Output format can be configured with optional `[--format <output-format>]` option. `<output-format>` supports [string interpolation](https://en.wikipedia.org/wiki/String_interpolation).

If not specified, the default `<output-format>` is:  
`%{app-pid}%{right-padding} | %{app-bundle-id}%{right-padding} | %{app-name}`

The following variables can be used inside `<output-format>`:

%{app-bundle-id}

: String. Application unique identifier. [Bundle ID](https://developer.apple.com/documentation/appstoreconnectapi/bundle_ids)

%{app-name}

: String. Application name

%{app-pid}

: Number. [UNIX process identifier](https://en.wikipedia.org/wiki/Process_identifier)

%{app-exec-path}

: String. Application executable path

%{app-bundle-path}

: String. Application bundle path

%{right-padding}

: A special variable which expands with a minimum number of spaces required to form a right padding in the appropriate column

%{newline}

: Unicode U+000A newline symbol `\n`

%{tab}

: Unicode U+0009 tab symbol `\t`

%{all}

: Includes all available variables. Can only be used with `--json` flag
