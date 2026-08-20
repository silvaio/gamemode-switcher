#!/usr/bin/env bash
# Enter / exit Omarchy Game Mode: snapshot desktop state, apply gaming
# optimizations, optionally launch Steam in Gamescope / Big Picture, restore
# on exit. Called from the silvaio.gamemode shell plugin.

set -u

SELF="$(readlink -f "$0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gamemode"
ACTIVE_FLAG="$STATE_DIR/active"
RESTORE="$STATE_DIR/restore.json"
STEAM_WINDOW="$STATE_DIR/steam-window.json"

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

# The Steam bootstrap daemonizes (and no-ops if a client is already running).
# Always wait on the real client pid, never on the launcher process.
steam_client_pid() {
  local pid=""
  if [[ -f "$HOME/.steam/steam.pid" ]]; then
    pid="$(tr -d '[:space:]' <"$HOME/.steam/steam.pid" 2>/dev/null || true)"
  fi
  if [[ -n "${pid}" && -d "/proc/${pid}" ]]; then
    printf '%s\n' "$pid"
    return 0
  fi
  pgrep -n -f '/ubuntu12_32/steam( |$)' 2>/dev/null || return 1
}

steam_client_running() {
  steam_client_pid >/dev/null 2>&1
}

wait_for_steam_client() {
  local timeout="${1:-40}" start now
  start="$(date +%s)"
  while ! steam_client_running; do
    now="$(date +%s)"
    if (( now - start >= timeout )); then
      return 1
    fi
    sleep 0.25
  done
}

wait_while_steam_client() {
  while steam_client_running && [[ -f "$ACTIVE_FLAG" ]]; do
    sleep 1
  done
}

# Game Mode should also end when Big Picture is closed, not only when Steam exits.
wait_while_steam_session() {
  local seen_bp=false
  while steam_client_running && [[ -f "$ACTIVE_FLAG" ]]; do
    if steam_big_picture_present; then
      seen_bp=true
    elif $seen_bp; then
      break
    fi
    sleep 0.5
  done
}

window_address_by_class() {
  local class="$1"
  hyprctl clients -j 2>/dev/null | jq -r --arg class "$class" '
    ([.[] | select((.class // "") == $class and .mapped == true)]
     | sort_by(-((.size[0] // 0) * (.size[1] // 0)))
     | .[0].address) // empty
  '
}

steam_session_window_address() {
  hyprctl clients -j 2>/dev/null | jq -r '
    def ui: (.class // "") == "steam" and .mapped == true;
    def session_ui: ((.title // "") | test("Big Picture|Gamepad UI|Steam Deck"; "i"));
    ([.[] | select(ui and session_ui)] + [.[] | select(ui)]
     | sort_by(-((.size[0] // 0) * (.size[1] // 0)))
     | .[0].address) // empty
  '
}

steam_big_picture_present() {
  hyprctl clients -j 2>/dev/null | jq -e '
    any(.[]; (.class // "") == "steam" and ((.title // "") | test("Big Picture|Gamepad UI|Steam Deck"; "i")))
  ' >/dev/null 2>&1
}

snapshot_steam_window() {
  hypr_available || return 0
  local json
  json="$(hyprctl clients -j 2>/dev/null | jq -c '
    def ui: (.class // "") == "steam" and .mapped == true;
    def bp: ((.title // "") | test("Big Picture|Gamepad UI|Steam Deck"; "i"));
    ([.[] | select(ui and (bp | not))] + [.[] | select(ui)]
     | sort_by(-((.size[0] // 0) * (.size[1] // 0)))
     | .[0] // null)
    | if . == null then empty else {
        workspace: (.workspace.id | tostring),
        floating: (.floating == true),
        x: .at[0],
        y: .at[1],
        w: .size[0],
        h: .size[1]
      } end
  ' 2>/dev/null || true)"
  [[ -n "$json" ]] || return 0
  printf '%s\n' "$json" >"$STEAM_WINDOW"
}

present_session_window() {
  local addr="$1" dest_ws="${2:-}" cur_ws=""
  [[ -n "$addr" ]] || return 1
  hypr_available || return 1
  if [[ -n "$dest_ws" ]]; then
    cur_ws="$(hyprctl clients -j 2>/dev/null | jq -r --arg addr "$addr" '
      first(.[] | select(.address == $addr) | .workspace.id) // empty
    ')"
    if [[ "$cur_ws" != "$dest_ws" ]]; then
      hyprctl dispatch "hl.dsp.window.move({ workspace = \"${dest_ws}\", window = \"address:${addr}\" })" >/dev/null 2>&1 || true
    fi
  fi
  hyprctl dispatch "hl.dsp.focus({ window = \"address:${addr}\" })" >/dev/null 2>&1 \
    || hyprctl dispatch focuswindow "address:${addr}" >/dev/null 2>&1 || true
  # Fullscreen in place. Do not float — that throws Steam out of the layout and
  # leaves a 1280x800 window at the corner when the session ends.
  hyprctl dispatch "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"set\", layout_aware = false, window = \"address:${addr}\" })" >/dev/null 2>&1 || true
}

current_workspace_id() {
  if [[ -f "$STATE_DIR/target-workspace" ]]; then
    tr -d '[:space:]' <"$STATE_DIR/target-workspace"
    return 0
  fi
  hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty'
}

focus_window_class() {
  local class="$1" dest_ws="${2:-}" addr
  hypr_available || return 1
  addr="$(window_address_by_class "$class")"
  [[ -n "$addr" ]] || return 1
  if [[ -z "$dest_ws" ]]; then
    dest_ws="$(current_workspace_id)"
  fi
  if [[ -n "$dest_ws" ]]; then
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"${dest_ws}\", window = \"address:${addr}\" })" >/dev/null 2>&1 || true
  fi
  hyprctl dispatch "hl.dsp.focus({ window = \"address:${addr}\" })" >/dev/null 2>&1 \
    || hyprctl dispatch focuswindow "address:${addr}" >/dev/null 2>&1
}

bring_steam_to_front() {
  local i dest_ws addr
  dest_ws="$(current_workspace_id)"
  for ((i = 1; i <= 48; i++)); do
    if steam_big_picture_present; then
      addr="$(steam_session_window_address)"
      present_session_window "$addr" "$dest_ws" || return 1
      return 0
    fi
    if focus_window_class gamescope "$dest_ws"; then
      return 0
    fi
    sleep 0.25
  done
  addr="$(steam_session_window_address)"
  [[ -n "$addr" ]] || return 1
  present_session_window "$addr" "$dest_ws"
}

shutdown_steam() {
  steam_client_running || return 0
  have steam && steam -shutdown >/dev/null 2>&1 || true
  local start now
  start="$(date +%s)"
  while steam_client_running; do
    now="$(date +%s)"
    if (( now - start >= 25 )); then
      return 1
    fi
    sleep 0.4
  done
}

run_detached() {
  if have uwsm-app; then
    setsid uwsm-app -- "$@" >/dev/null 2>&1 &
  else
    setsid "$@" >/dev/null 2>&1 &
  fi
}

start_steam_gamepad_ui() {
  if ! have steam; then
    gtk-launch steam >/dev/null 2>&1 || gtk-launch com.valvesoftware.Steam >/dev/null 2>&1 || true
    return 0
  fi
  if steam_client_running; then
    # -gamepadui is only a start flag. An already-running client needs the URI.
    steam steam://open/bigpicture >/dev/null 2>&1 || steam -gamepadui >/dev/null 2>&1 || true
    return 0
  fi
  setsid steam -gamepadui </dev/null >>"$STATE_DIR/session.log" 2>&1 &
}

run_gamescope_steam() {
  have gamescope && have steam || return 1
  if steam_client_running; then
    notify "Restarting Steam inside Gamescope"
    shutdown_steam || return 1
  fi
  # --steam/-e keeps gamescope alive after Steam's bootstrap process exits.
  gamescope -e -f -- steam -gamepadui -steamdeck
}

run_steam_session() {
  mkdir -p "$STATE_DIR"
  if gamescope_available && steam_available; then
    if run_gamescope_steam; then
      return 0
    fi
    notify "Gamescope failed — using Steam Big Picture"
  fi
  if steam_available; then
    start_steam_gamepad_ui
    if ! wait_for_steam_client 45; then
      notify "Steam failed to start"
      return 1
    fi
    bring_steam_to_front || true
    wait_while_steam_session
    return 0
  fi
  notify "Steam is not installed. Install it from Omarchy → Install → Gaming → Steam."
  return 1
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
      [[ -f "$STATE_DIR/session.id" ]] || printf '%s\n' "$$-$RANDOM-$(date +%s)" >"$STATE_DIR/session.id"
      if hypr_available && [[ ! -s "$STATE_DIR/target-workspace" ]]; then
        hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty' >"$STATE_DIR/target-workspace"
      fi
      [[ -f "$STEAM_WINDOW" ]] || snapshot_steam_window
      cmd_launch_steam_session
    fi
    return 0
  fi

  snapshot
  apply_gaming
  touch "$ACTIVE_FLAG"

  if $steam_gamescope; then
    printf '%s\n' "$$-$RANDOM-$(date +%s)" >"$STATE_DIR/session.id"
    if hypr_available; then
      hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty' >"$STATE_DIR/target-workspace"
    fi
    snapshot_steam_window
    notify "ON — launching Steam"
    cmd_launch_steam_session
  else
    notify "ON — desktop optimized"
  fi
}

cmd_launch_steam_session() {
  # Detach so Game Mode does not restore the moment Steam's launcher exits.
  mkdir -p "$STATE_DIR"
  setsid -f "$SELF" wait-steam-session >>"$STATE_DIR/session.log" 2>&1
}

cmd_wait_steam_session() {
  local sid=""
  [[ -f "$STATE_DIR/session.id" ]] && sid="$(tr -d '[:space:]' <"$STATE_DIR/session.id")"
  run_steam_session || true
  local now=""
  [[ -f "$STATE_DIR/session.id" ]] && now="$(tr -d '[:space:]' <"$STATE_DIR/session.id")"
  if [[ -f "$ACTIVE_FLAG" && -n "$sid" && "$sid" == "$now" ]]; then
    "$SELF" exit
  fi
}

restore_steam_desktop_window() {
  local addr json ws floating x y w h
  hypr_available || return 0
  addr="$(steam_session_window_address)"
  [[ -n "$addr" ]] || addr="$(window_address_by_class steam)"
  [[ -n "$addr" ]] || return 0

  hyprctl dispatch "hl.dsp.window.fullscreen({ action = \"unset\", layout_aware = false, window = \"address:${addr}\" })" >/dev/null 2>&1 || true

  if [[ ! -f "$STEAM_WINDOW" ]]; then
    hyprctl dispatch "hl.dsp.window.float({ action = \"off\", window = \"address:${addr}\" })" >/dev/null 2>&1 || true
    return 0
  fi

  json="$(cat "$STEAM_WINDOW")"
  ws="$(jq -r '.workspace // empty' <<<"$json")"
  floating="$(jq -r '.floating // false' <<<"$json")"
  x="$(jq -r '.x // empty' <<<"$json")"
  y="$(jq -r '.y // empty' <<<"$json")"
  w="$(jq -r '.w // empty' <<<"$json")"
  h="$(jq -r '.h // empty' <<<"$json")"

  if [[ -n "$ws" ]]; then
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"${ws}\", follow = false, window = \"address:${addr}\" })" >/dev/null 2>&1 || true
  fi

  if [[ "$floating" == "true" ]]; then
    hyprctl dispatch "hl.dsp.window.float({ action = \"on\", window = \"address:${addr}\" })" >/dev/null 2>&1 || true
    if [[ -n "$x" && -n "$y" ]]; then
      hyprctl dispatch "hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = \"address:${addr}\" })" >/dev/null 2>&1 || true
    fi
    if [[ -n "$w" && -n "$h" ]]; then
      hyprctl dispatch "hl.dsp.window.resize({ x = ${w}, y = ${h}, relative = false, window = \"address:${addr}\" })" >/dev/null 2>&1 || true
    fi
  else
    hyprctl dispatch "hl.dsp.window.float({ action = \"off\", window = \"address:${addr}\" })" >/dev/null 2>&1 || true
  fi
}

cmd_exit() {
  restore_steam_desktop_window
  if [[ -f "$RESTORE" ]]; then
    restore_desktop
  else
    # No snapshot (already exited, or enter failed mid-way): still unhide the bar.
    set_bar_hidden false
  fi
  rm -f "$ACTIVE_FLAG" "$RESTORE" "$STEAM_WINDOW" "$STATE_DIR/session.id" "$STATE_DIR/target-workspace"
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
      if focus_window_class steam; then
        :
      elif steam_client_running && have steam; then
        steam steam://open/games >/dev/null 2>&1 || true
        bring_steam_to_front || true
      elif have steam; then
        run_detached steam
      else
        run_detached gtk-launch steam
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
  wait-steam-session) cmd_wait_steam_session ;;
  *)
    echo "Usage: gamemode.sh enter [--steam-gamescope] | exit | status | launchers | launch <id>" >&2
    exit 1
    ;;
esac
