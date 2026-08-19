#!/usr/bin/env bash
# Enter / exit Omarchy Game Mode: snapshot desktop state, apply gaming
# optimizations, optionally launch Steam in Gamescope / Big Picture, restore
# on exit. Called from the silvaio.gamemode shell plugin.

set -u

SELF="$(readlink -f "$0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gamemode"
ACTIVE_FLAG="$STATE_DIR/active"
RESTORE="$STATE_DIR/restore.json"

mkdir -p "$STATE_DIR"

have() { command -v "$1" >/dev/null 2>&1; }

notify() {
  if have notify-send; then
    notify-send -i applications-games "Game Mode" "$1" || true
  fi
}

desktop_exists() {
  local name="$1"
  [[ -f "/usr/share/applications/${name}.desktop" ]] \
    || [[ -f "$HOME/.local/share/applications/${name}.desktop" ]]
}

bar_hidden() { [[ -f "$HOME/.local/state/omarchy/toggles/bar-off" ]]; }

dnd_on() {
  local state
  state="$(omarchy-shell notifications isDnd 2>/dev/null || echo off)"
  [[ "${state,,}" == "on" ]]
}

nightlight_on() {
  local json enabled
  json="$(omarchy-toggle-nightlight --status 2>/dev/null || echo '{}')"
  enabled="$(jq -r '.enabled // false' <<<"$json" 2>/dev/null || echo false)"
  [[ "$enabled" == "true" ]]
}

stay_awake_on() {
  [[ -f "$HOME/.local/state/omarchy/indicators/stay-awake" ]]
}

hypr_available() {
  have hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" || -n "$(hyprctl instances 2>/dev/null | head -n1)" ]]
}

hypr_value() {
  local opt="$1" raw
  raw="$(hyprctl getoption "$opt" -j 2>/dev/null || echo "")"
  [[ -n "$raw" ]] || { echo ""; return; }
  # Current hyprctl JSON uses bool/css/int. Older builds used custom/int only.
  jq -r '
    if has("bool") then (if .bool then "1" else "0" end)
    elif .int != null then (.int | tostring)
    elif .float != null then (.float | tostring)
    elif (.css // "") != "" then .css
    elif (.custom // "") != "" and .custom != "null" then .custom
    elif (.str // "") != "" then .str
    else empty
    end
  ' <<<"$raw" 2>/dev/null || true
}

hypr_set() {
  local opt="$1" val="$2"
  [[ -n "$val" ]] || return 0
  hyprctl keyword "$opt" "$val" >/dev/null 2>&1 || true
}

power_profile() {
  have powerprofilesctl && powerprofilesctl get 2>/dev/null || echo ""
}

set_power_profile() {
  local profile="$1"
  [[ -n "$profile" ]] || return 0
  have powerprofilesctl && powerprofilesctl set "$profile" >/dev/null 2>&1 || true
}

set_bar_hidden() {
  # `omarchy toggle bar on` means "turn bar-off on" — it HIDES the bar.
  # Always drive the bar-off flag explicitly, then poke the toggles
  # directory so the shell FileView re-probes. Deleting the flag alone
  # can leave the running shell parked off-screen.
  local toggles="$HOME/.local/state/omarchy/toggles"
  mkdir -p "$toggles"
  if [[ "$1" == "true" ]]; then
    omarchy-toggle bar-off on
  else
    omarchy-toggle bar-off off
  fi
  touch "$toggles"
}

set_dnd() {
  omarchy-shell notifications setDnd "$1" >/dev/null 2>&1 || true
}

set_nightlight() {
  local want="$1"
  local now
  now="$(nightlight_on && echo true || echo false)"
  if [[ "$now" != "$want" ]]; then
    omarchy-toggle-nightlight >/dev/null 2>&1 || true
  fi
}

set_stay_awake() {
  if [[ "$1" == "true" ]]; then
    omarchy-toggle-idle stay-awake >/dev/null 2>&1 || true
  else
    omarchy-toggle-idle allow-idle >/dev/null 2>&1 || true
  fi
}

steam_available() {
  have steam || desktop_exists steam || desktop_exists com.valvesoftware.Steam
}

gamescope_available() { have gamescope; }

run_detached() {
  if have uwsm-app; then
    setsid uwsm-app -- "$@" >/dev/null 2>&1 &
  else
    setsid "$@" >/dev/null 2>&1 &
  fi
}

run_steam_session() {
  if gamescope_available && steam_available; then
    # Nested fullscreen Gamescope session with Steam's Deck / Big Picture UI.
    if have steam; then
      gamescope -f -- steam -gamepadui
    else
      gamescope -f -- gtk-launch steam
    fi
  elif steam_available; then
    if have steam; then
      if have uwsm-app; then
        uwsm-app -- steam -gamepadui
      else
        steam -gamepadui
      fi
    else
      gtk-launch steam
    fi
  else
    notify "Steam is not installed. Install it from Omarchy → Install → Gaming → Steam."
    return 1
  fi
}

snapshot() {
  local hypr_json="{}"
  if hypr_available; then
    hypr_json="$(jq -cn \
      --arg animations "$(hypr_value animations:enabled)" \
      --arg blur "$(hypr_value decoration:blur:enabled)" \
      --arg shadow "$(hypr_value decoration:shadow:enabled)" \
      --arg gaps_in "$(hypr_value general:gaps_in)" \
      --arg gaps_out "$(hypr_value general:gaps_out)" \
      --arg border "$(hypr_value general:border_size)" \
      --arg rounding "$(hypr_value decoration:rounding)" \
      '{
        animations: $animations,
        blur: $blur,
        shadow: $shadow,
        gaps_in: $gaps_in,
        gaps_out: $gaps_out,
        border: $border,
        rounding: $rounding
      }')"
  fi

  jq -cn \
    --argjson barHidden "$(bar_hidden && echo true || echo false)" \
    --argjson dnd "$(dnd_on && echo true || echo false)" \
    --argjson nightlight "$(nightlight_on && echo true || echo false)" \
    --argjson stayAwake "$(stay_awake_on && echo true || echo false)" \
    --arg power "$(power_profile)" \
    --argjson hypr "$hypr_json" \
    '{
      barHidden: $barHidden,
      dnd: $dnd,
      nightlight: $nightlight,
      stayAwake: $stayAwake,
      power: $power,
      hypr: $hypr
    }' >"$RESTORE"
}

apply_gaming() {
  set_dnd on
  set_nightlight false
  set_stay_awake true
  set_power_profile performance

  if hypr_available; then
    hyprctl --batch "\
      keyword animations:enabled 0;\
      keyword decoration:blur:enabled 0;\
      keyword decoration:shadow:enabled 0;\
      keyword general:gaps_in 0;\
      keyword general:gaps_out 0;\
      keyword general:border_size 1;\
      keyword decoration:rounding 0" >/dev/null 2>&1 || true
  fi
}

restore_desktop() {
  [[ -f "$RESTORE" ]] || return 0
  local json animations
  json="$(cat "$RESTORE")"

  set_bar_hidden "$(jq -r '.barHidden // false' <<<"$json")"
  if [[ "$(jq -r '.dnd // false' <<<"$json")" == "true" ]]; then
    set_dnd on
  else
    set_dnd off
  fi
  set_nightlight "$(jq -r '.nightlight // false' <<<"$json")"
  set_stay_awake "$(jq -r '.stayAwake // false' <<<"$json")"
  set_power_profile "$(jq -r '.power // empty' <<<"$json")"

  if hypr_available; then
    animations="$(jq -r '.hypr.animations // empty' <<<"$json")"
    if [[ -z "$animations" && -z "$(jq -r '.hypr.gaps_in // empty' <<<"$json")" ]]; then
      hyprctl reload >/dev/null 2>&1 || true
    else
      hypr_set animations:enabled "$animations"
      hypr_set decoration:blur:enabled "$(jq -r '.hypr.blur // empty' <<<"$json")"
      hypr_set decoration:shadow:enabled "$(jq -r '.hypr.shadow // empty' <<<"$json")"
      hypr_set general:gaps_in "$(jq -r '.hypr.gaps_in // empty' <<<"$json")"
      hypr_set general:gaps_out "$(jq -r '.hypr.gaps_out // empty' <<<"$json")"
      hypr_set general:border_size "$(jq -r '.hypr.border // empty' <<<"$json")"
      hypr_set decoration:rounding "$(jq -r '.hypr.rounding // empty' <<<"$json")"
    fi
  fi

  rm -f "$RESTORE"
}

cmd_enter() {
  local steam_gamescope=false
  for arg in "$@"; do
    case "$arg" in
      --steam-gamescope) steam_gamescope=true ;;
      --no-steam) steam_gamescope=false ;;
    esac
  done

  if [[ -f "$ACTIVE_FLAG" ]]; then
    if $steam_gamescope; then
      cmd_launch_steam_session
    fi
    return 0
  fi

  snapshot
  apply_gaming
  touch "$ACTIVE_FLAG"

  if $steam_gamescope; then
    notify "ON — launching Steam"
    cmd_launch_steam_session
  else
    notify "ON — desktop optimized"
  fi
}

cmd_launch_steam_session() {
  # When the Gamescope / Big Picture session ends, restore the desktop.
  (
    run_steam_session || true
    if [[ -f "$ACTIVE_FLAG" ]]; then
      "$SELF" exit
    fi
  ) >/dev/null 2>&1 &
}

cmd_exit() {
  if [[ -f "$RESTORE" ]]; then
    restore_desktop
  else
    # No snapshot (already exited, or enter failed mid-way): still unhide the bar.
    set_bar_hidden false
  fi
  rm -f "$ACTIVE_FLAG" "$RESTORE"
  notify "OFF — desktop restored"
}

cmd_status() {
  jq -cn \
    --argjson active "$([[ -f "$ACTIVE_FLAG" ]] && echo true || echo false)" \
    --argjson steam "$(steam_available && echo true || echo false)" \
    --argjson gamescope "$(gamescope_available && echo true || echo false)" \
    '{active: $active, steam: $steam, gamescope: $gamescope}'
}

cmd_launchers() {
  local items="[]"

  add() {
    local id="$1" name="$2"
    items="$(jq -c --arg id "$id" --arg name "$name" '. + [{id: $id, name: $name}]' <<<"$items")"
  }

  if steam_available; then add steam Steam; fi
  if have retroarch || desktop_exists retroarch || desktop_exists org.libretro.RetroArch; then
    add retroarch RetroArch
  fi
  if have prismlauncher || have minecraft-launcher || desktop_exists org.prismlauncher.PrismLauncher; then
    add minecraft Minecraft
  fi
  if have lutris || desktop_exists net.lutris.Lutris; then add lutris Lutris; fi
  if have heroic || desktop_exists com.heroicgameslauncher.hgl; then add heroic Heroic; fi
  if have geforcenow || desktop_exists nvidia-geforcenow || desktop_exists com.nvidia.geforcenow; then
    add geforcenow "GeForce NOW"
  fi

  echo "$items"
}

cmd_launch() {
  local id="${1:-}"
  case "$id" in
    steam)
      if have steam; then run_detached steam
      else run_detached gtk-launch steam
      fi
      ;;
    retroarch)
      if have retroarch; then run_detached retroarch
      else run_detached gtk-launch org.libretro.RetroArch
      fi
      ;;
    minecraft)
      if have prismlauncher; then run_detached prismlauncher
      elif have minecraft-launcher; then run_detached minecraft-launcher
      else run_detached gtk-launch org.prismlauncher.PrismLauncher
      fi
      ;;
    lutris)
      if have lutris; then run_detached lutris
      else run_detached gtk-launch net.lutris.Lutris
      fi
      ;;
    heroic)
      if have heroic; then run_detached heroic
      else run_detached gtk-launch com.heroicgameslauncher.hgl
      fi
      ;;
    geforcenow)
      if have geforcenow; then run_detached geforcenow
      elif desktop_exists nvidia-geforcenow; then run_detached gtk-launch nvidia-geforcenow
      else xdg-open "https://play.geforcenow.com" >/dev/null 2>&1 &
      fi
      ;;
    *)
      echo "unknown launcher: $id" >&2
      return 1
      ;;
  esac
}

case "${1:-}" in
  enter) shift; cmd_enter "$@" ;;
  exit) cmd_exit ;;
  status) cmd_status ;;
  launchers) cmd_launchers ;;
  launch) shift; cmd_launch "$@" ;;
  *)
    echo "Usage: gamemode.sh enter [--steam-gamescope] | exit | status | launchers | launch <id>" >&2
    exit 1
    ;;
esac
