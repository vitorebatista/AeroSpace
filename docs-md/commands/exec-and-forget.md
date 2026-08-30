---
title: exec-and-forget
description: Run /bin/bash -c '<bash-script>'
section: 1
---

# aerospace-edge exec-and-forget

Run /bin/bash -c '<bash-script>'

## Synopsis

```synopsis
aerospace-edge exec-and-forget <bash-script>
```

## Description

Run `/bin/bash -c '<bash-script>'`, and don’t wait for the command termination. Stdout, stderr and exit code are ignored.

For example, you can use this command to launch applications:

``` toml
alt-enter = 'exec-and-forget open -n /System/Applications/Utilities/Terminal.app'
```

`<bash-script>` is passed "as is" to bash without any transformations and escaping. `<bash-script>` is treated as suffix of the TOML string, it’s not even an argument in classic CLI sense

- The command is available in config

- The command is **NOT** available in CLI
