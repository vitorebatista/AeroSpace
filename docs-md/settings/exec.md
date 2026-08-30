# Exec

**Where:** menu bar → **Settings…** → **Exec**

![The Exec destination, showing environment inheritance and variable override rows](../assets/settings-exec.jpg)

The environment handed to every [`exec-and-forget`](../commands/exec-and-forget.md) command
AeroSpace-edge runs — including the ones in callbacks and window rules.

## Environment

### Inherit environment variables from the launching process

Uses the environment AeroSpace-edge itself was launched with as the base. Turn it off and a
command starts with only your explicit overrides plus the variables AeroSpace-edge provides
— which means no `PATH`, so commands must be given as absolute paths.

**TOML** `exec.inherit-env-vars` · **values** `true` / `false` · **default** `true` ·
**applies** to commands run after reload

## Environment variable overrides

Adds or replaces variables for every `exec-and-forget`. `$VAR` interpolates the inherited
value, so a variable can extend rather than replace itself:

```toml
[exec.env-vars]
PATH = '/opt/homebrew/bin:$PATH'
TERM = 'xterm-256color'
```

`PWD` is managed by AeroSpace-edge and is rejected.

**TOML** `[exec.env-vars]` · **default** no authored overrides · **applies** to commands run
after reload · see [Exec environment](../guide.md#exec-env-vars)

!!! warning "Whole-family rewrite"

    Changing either control on this page regenerates the complete `exec` family, including
    `[exec.env-vars]`. Comments inside it do not survive the Save.
