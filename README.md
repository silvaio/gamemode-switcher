# Game Mode Switcher

One-click **Game Mode** for Omarchy Quattro.

- Hide the bar (`omarchy toggle bar`, same flag as `Super + Shift + Space`)
- Do-not-disturb, stay-awake, night light off, performance power profile
- Disable Hyprland animations, blur, shadows, and gaps — then restore the previous values on exit
- Optional: launch Steam in Gamescope (or Big Picture if Gamescope is missing). Quitting Steam restores the desktop
- Quick-launch only the game clients you actually have installed

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

- Click the gamepad chip in the bar
- Enter / Exit Game Mode with the switch or the button
- Enable **Steam in Gamescope** in the panel (or in widget settings) if you want Enter to start a Steam Deck-style session

When the bar is hidden, `Super + Shift + Space` shows it again so you can exit.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `steamGamescope` | `false` | Enter Game Mode launches Steam's Deck UI in Gamescope when available, otherwise Steam Big Picture. Quitting Steam exits Game Mode. |

```sh
omarchy bar set silvaio.gamemode steamGamescope true
```

## Remove

```sh
omarchy plugin remove silvaio.gamemode
```

## License

MIT
