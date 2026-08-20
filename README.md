# Game Mode Switcher

One-click **Game Mode** for Omarchy Quattro.

- Do-not-disturb, stay-awake, night light off, performance power profile
- Disable Hyprland animations, blur, shadows, and gaps — then restore the previous values on exit
- Optional **Gamescope session**: Steam Deck UI in Gamescope, or Steam Big Picture if Gamescope is missing
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
- Flip **Game Mode** to enter or leave
- Optionally enable **Gamescope session** before entering

Optional keybind:

```lua
o.bind("SUPER + CTRL + G", "Game Mode", "omarchy-shell silvaio.gamemode toggleMode")
```

```sh
omarchy bar set silvaio.gamemode steamGamescope true
```

## Gamescope session

When **Gamescope session** is on, entering Game Mode starts a Steam session and **keeps Game Mode on until Steam actually quits** (or you flip the switch off).

| Gamescope installed? | Steam already running? | What happens |
|---|---|---|
| Yes | No | Nested fullscreen Gamescope with Steam Deck UI |
| Yes | Yes | Steam is shut down, then restarted inside Gamescope |
| No | No | Steam starts in gamepad / Big Picture UI |
| No | Yes | The running client is sent to Big Picture (`steam://open/bigpicture`) |

Without Gamescope, Big Picture is moved onto the workspace you were on and fullscreened. That still works on a busy workspace and with Omarchy's dwindle or scrolling layout (`SUPER + L`). Game Mode does not change the workspace layout itself.

The Steam quick-launch button only focuses (and, if needed, moves) the existing Steam window. It does not enter Big Picture.

### Leaving

- **Quit Steam** from Big Picture / Gamescope — Game Mode restores the desktop
- **Flip Game Mode off** — desktop settings are restored. Steam may stay in Big Picture until you use Steam's own Exit Big Picture / Switch to desktop

## Settings

| Key | Default | Meaning |
|---|---|---|
| `steamGamescope` | `false` | Enter Game Mode launches a Steam Gamescope / Big Picture session. Quitting Steam exits Game Mode. |

## Dependencies

Ships with Omarchy: `hyprctl`, `jq`, `notify-send`, and usually `powerprofilesctl`.

Optional, only if you enable the Gamescope session:

- Steam (`steam` or the Steam desktop entry)
- Gamescope (`gamescope`) — without it, Game Mode uses Steam Big Picture

```sh
omarchy pkg add gamescope
```

## Remove

Exit Game Mode first so notifications, idle, power profile, and Hyprland settings are restored. Then:

```sh
omarchy plugin remove silvaio.gamemode
```

## License

MIT
