# Omakeycast

On-screen keybinding overlay for [Omarchy](https://omarchy.org/). While you
record your screen, Super, Ctrl, and Alt combinations appear at the bottom
right of every monitor for a short time, on top of other windows.

Bare keys and Shift-only typing stay hidden. Shift is included only when it
is held together with Super, Ctrl, or Alt:

- `Super + Ctrl + Return`
- `Ctrl + A`
- `Alt + Tab`
- `Ctrl + Shift + A`

## Install

```sh
omarchy plugin add https://github.com/fredimachado/omakeycast.git --enable
```

The overlay starts as soon as the plugin is enabled. It does not add a bar
widget.

### Keyboard access

Omakeycast reads keyboard events from `/dev/input` without grabbing the
device, so it never steals keys from apps or Hyprland. Your user must be in
the `input` group:

```sh
sudo usermod -aG input "$USER"
```

Log out and back in after that. Until the group is active, the overlay shows
a reminder instead of key combos.

## Configure

Settings live inline on the plugin entry in `~/.config/omarchy/shell.json`.
The file reloads on save.

```json
{
  "plugins": [
    {
      "id": "io.github.fredimachado.omakeycast",
      "duration": 2,
      "fontSize": 28,
      "position": "bottom-right"
    }
  ]
}
```

| Setting    | Default          | Meaning                                              |
| ---------- | ---------------- | ---------------------------------------------------- |
| `duration` | `2`              | Seconds the combo stays visible                      |
| `fontSize` | `28`             | Label size in pixels                                 |
| `position` | `bottom-right`   | `bottom-right`, `bottom-left`, `top-right`, `top-left` |

## Usage

Press any Super, Ctrl, or Alt combination. The HUD appears on every screen,
ignores mouse clicks, and fades after `duration` seconds. A new combo resets
the timer.

To preview the overlay without pressing a shortcut:

```sh
omarchy-shell omakeycast show '{"text":"Super + Ctrl + Return"}'
```

Hide it with Escape from that preview, or:

```sh
omarchy-shell omakeycast close
```

## Remove

```sh
omarchy plugin remove io.github.fredimachado.omakeycast
```

## Development

```sh
make check
```

That validates the manifest, runs the combo and settings tests, and lints
`Overlay.qml` against the installed Omarchy shell imports.

`qmllint` may warn that it cannot resolve `qs.Commons` / `qs.Ui` outside a
running Quickshell session. The same imports are used by first-party plugins
such as the OSD.

## License

MIT
