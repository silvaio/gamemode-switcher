# Game Mode Switcher

One-click **Game Mode** for Omarchy Quattro.

- Do-not-disturb, stay-awake, night light off, performance power profile
- Disable Hyprland animations, blur, shadows, and gaps — then restore the previous values on exit
- Optional: launch Steam in Gamescope (or Big Picture if Gamescope is missing). Quitting Steam restores the desktop
- Quick-launch only the game clients you actually have installed

The bar stays. The gamepad chip is how you leave.

## Install

```sh
omarchy plugin add https://github.com/silvaio/gamemode-switcher.git --enable
```

Or develop locally:

```sh
mkdir -p ~/.config/omarchy/plugins
cp -a . ~/.config/omarchy/plugins/silvaio.gamemode
omarchy plugin validate ~/.config/omarchy/plugins/silvaio.gamemode
omarchy plugin enable silvaio.gamemode --section right
```

## Usage

- Click the gamepad chip
- Flip the switch to enter or leave

Optional keybind:

```lua
o.bind("SUPER + CTRL + G", "Game Mode", "omarchy-shell silvaio.gamemode toggleMode")
```

## Settings

| Key | Default | Meaning |
|---|---|---|
| `steamGamescope` | `false` | Enter Game Mode launches Steam's Deck UI in Gamescope when available, otherwise Steam Big Picture. Quitting Steam exits Game Mode. |

```sh
omarchy bar set silvaio.gamemode steamGamescope true
```

## Dependencies

Ships with Omarchy: `hyprctl`, `jq`, `notify-send`, and usually `powerprofilesctl`.

Optional, only if you enable the Gamescope session:

- Steam (`steam` or the Steam desktop entry)
- Gamescope (`gamescope`) — without it, Game Mode falls back to Steam Big Picture

## Remove

Exit Game Mode first so notifications, idle, power profile, and Hyprland settings are restored. Then:

```sh
omarchy plugin remove silvaio.gamemode
```

## License

MIT
