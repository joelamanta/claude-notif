#!/usr/bin/env bash
# Shared profile-aware config reader for Noto hooks.
# Set NOTIF_PROFILE to claude, cursor, or codex before sourcing.

if [ -z "${CONFIG_FILE:-}" ]; then
  if [ -f "$HOME/.noto/notifications.json" ]; then
    CONFIG_FILE="$HOME/.noto/notifications.json"
  else
    CONFIG_FILE="$HOME/.claude/notifications.json"
  fi
fi

cfg_root_enabled() {
  [ "$(jq -r '.enabled // true' "$CONFIG_FILE" 2>/dev/null)" != "false" ]
}

cfg_profile_enabled() {
  local profile="${NOTIF_PROFILE:-cursor}"
  [ "$(jq -r ".${profile}.enabled // true" "$CONFIG_FILE" 2>/dev/null)" != "false" ]
}

cfg_enabled() {
  cfg_root_enabled && cfg_profile_enabled
}

cfg_snoozed() {
  local snooze_file="$HOME/.noto/snooze-until"
  local until_ts now_ts
  [ -f "$snooze_file" ] || return 1
  until_ts=$(tr -d '[:space:]' < "$snooze_file" 2>/dev/null)
  [ -n "$until_ts" ] || return 1
  now_ts=$(date +%s)
  [ "$now_ts" -lt "$until_ts" ]
}

cfg_should_notify() {
  cfg_enabled || return 1
  cfg_snoozed && return 1
  cfg_mac_focus_blocked && return 1
  return 0
}

cfg_mac_focus_blocked() {
  [ "$(jq -r '.respectMacFocus // true' "$CONFIG_FILE" 2>/dev/null)" != "true" ] && return 1
  local state_file="$HOME/.noto/mac-focus-active"
  [ -f "$state_file" ] && [ "$(tr -d '[:space:]' < "$state_file")" = "1" ]
}

cfg_noto_focus_allows_kind() {
  local kind="$1"
  local mode
  mode="$(jq -r '.focusMode // "available"' "$CONFIG_FILE" 2>/dev/null)"
  [ "$mode" != "deepWork" ] && return 0
  [ "$kind" = "done" ]
}

cfg_val() {
  local key="$1"
  local default="$2"
  local profile="${NOTIF_PROFILE:-cursor}"
  jq -r ".${profile}.${key} // .${key} // \"${default}\"" "$CONFIG_FILE" 2>/dev/null
}

longtimer_active_file() {
  printf '/tmp/%s-longtimer-active' "$1"
}

longtimer_pid_file() {
  printf '/tmp/%s-longtimer-%s.pid' "$1" "$2"
}

mark_profile_active() {
  date +%s > "$(longtimer_active_file "$1")"
  rm -f "/tmp/${1}-longtimer-finished-at"
}

mark_profile_idle() {
  rm -f "$(longtimer_active_file "$1")"
  date +%s > "/tmp/${1}-longtimer-finished-at"
}

profile_still_active() {
  [ -f "$(longtimer_active_file "$1")" ]
}

longtimer_recently_finished() {
  local profile="$1"
  local finished_file="/tmp/${profile}-longtimer-finished-at"
  local finished_at now
  [ -f "$finished_file" ] || return 1
  finished_at=$(cat "$finished_file" 2>/dev/null)
  [ -n "$finished_at" ] || return 1
  now=$(date +%s)
  [ $((now - finished_at)) -lt 120 ]
}

_longtimer_kill_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null || true
  sleep 0.05
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
}

_longtimer_remove_pid_file() {
  local pid_file="$1"
  local pid
  [ -f "$pid_file" ] || return 0
  pid=$(cat "$pid_file" 2>/dev/null)
  _longtimer_kill_pid "$pid"
  rm -f "$pid_file"
}

cancel_long_timers() {
  local profile="$1"
  local pid_file

  mark_profile_idle "$profile"

  shopt -s nullglob 2>/dev/null || true
  for pid_file in \
    /tmp/${profile}-longtimer-*.pid \
    /tmp/${profile}-longtimer-*-*-*.pid; do
    _longtimer_remove_pid_file "$pid_file"
  done
  for pid_file in /tmp/${profile}-longtimer-active-*; do
    [ -f "$pid_file" ] || continue
    rm -f "$pid_file"
  done
  shopt -u nullglob 2>/dev/null || true
}

finish_long_timers() {
  cancel_long_timers "$1"
}

longtimer_should_fire() {
  local profile="$1"
  local pid_file="$2"
  profile_still_active "$profile" || return 1
  [ -f "$pid_file" ] || return 1
  [ "$(cat "$pid_file" 2>/dev/null)" = "$$" ] || return 1
  return 0
}

start_long_timers() {
  local profile="$1"
  local session_id="$2"
  local queue_file="$3"
  local open_app="$4"
  local thresholds_expr="$5"
  local lr_sound lr_vol lr_prefix lr_thresholds lr_minutes lr_pid_file existing_pid

  cfg_enabled || return 0
  [ "$(cfg_val enableLongRunning false)" = "true" ] || return 0
  # session_id is optional; Cursor preToolUse and afterAgentResponse can disagree.
  [ -n "$session_id" ] || session_id="active"

  mark_profile_active "$profile"

  lr_sound="$(cfg_val soundLongRunning "Glass")"
  lr_vol="$(cfg_val volumeLongRunning "1.0")"
  lr_prefix="$(cfg_val titlePrefix "$open_app")"
  [ -z "$lr_prefix" ] && lr_prefix="$open_app"
  lr_thresholds=$(jq -r "$thresholds_expr" "$CONFIG_FILE" 2>/dev/null)

  for lr_minutes in $lr_thresholds; do
    lr_pid_file="$(longtimer_pid_file "$profile" "$lr_minutes")"
    existing_pid=""
    [ -f "$lr_pid_file" ] && existing_pid=$(cat "$lr_pid_file" 2>/dev/null)
    if [ -z "$existing_pid" ] || ! kill -0 "$existing_pid" 2>/dev/null; then
      (
        sleep $((lr_minutes * 60))
        longtimer_should_fire "$profile" "$lr_pid_file" || exit 0
        cfg_in_quiet_hours && exit 0
        profile_still_active "$profile" || exit 0
        longtimer_recently_finished "$profile" && exit 0
        notify_queue "$queue_file" "$profile" "$open_app" \
          "⏱ $lr_prefix" "Still running — ${lr_minutes}m elapsed" \
          "A task is taking longer than expected." "$lr_sound" "$lr_vol" "longrun"
        rm -f "$lr_pid_file"
      ) </dev/null >/dev/null 2>&1 &
      disown 2>/dev/null
      echo $! > "$lr_pid_file"
    fi
  done
}

preview_body() {
  local raw_text="$1"
  local mode="${2:-sentence}"
  local preview_script=""

  if [ -n "${NOTO_PREVIEW_SCRIPT:-}" ] && [ -f "$NOTO_PREVIEW_SCRIPT" ]; then
    preview_script="$NOTO_PREVIEW_SCRIPT"
  else
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for candidate in \
      "$lib_dir/preview-text.py" \
      "$HOME/.cursor/hooks/preview-text.py" \
      "$HOME/.claude/hooks/preview-text.py" \
      "$HOME/.codex/hooks/preview-text.py"; do
      if [ -f "$candidate" ]; then
        preview_script="$candidate"
        break
      fi
    done
  fi

  if [ -z "$preview_script" ]; then
    printf '%s' "${raw_text:0:80}"
    return
  fi

  local out
  out=$(printf '%s' "$raw_text" | python3 "$preview_script" "$mode" 2>/dev/null)
  if [ -n "$out" ]; then
    printf '%s' "$out"
  else
    printf '%s' "${raw_text:0:80}"
  fi
}

cfg_in_quiet_hours() {
  [ "$(cfg_val quietEnabled false)" != "true" ] && return 1

  local quiet_from quiet_to now_m from_m to_m
  quiet_from="$(cfg_val quietFrom "22:00")"
  quiet_to="$(cfg_val quietTo "08:00")"
  now_m=$((10#$(date +%H) * 60 + 10#$(date +%M)))
  from_m=$((10#${quiet_from%%:*} * 60 + 10#${quiet_from##*:}))
  to_m=$((10#${quiet_to%%:*} * 60 + 10#${quiet_to##*:}))

  if [ "$from_m" -le "$to_m" ]; then
    [ "$now_m" -ge "$from_m" ] && [ "$now_m" -lt "$to_m" ]
  else
    { [ "$now_m" -ge "$from_m" ] || [ "$now_m" -lt "$to_m" ]; }
  fi
}

notify_queue() {
  local queue_file="$1"
  local profile="$2"
  local open_app="$3"
  local title="$4"
  local subtitle="${5:-}"
  local body="$6"
  local sound="$7"
  local volume="$8"
  local kind="${9:-done}"
  local pid_file="/tmp/noto-menubar.pid"

  case "$kind" in
    done|alert) finish_long_timers "$profile" ;;
  esac

  cfg_should_notify || return 0
  cfg_noto_focus_allows_kind "$kind" || return 0
  cfg_snoozed && return 0

  jq -n \
    --arg profile "$profile" \
    --arg openApp "$open_app" \
    --arg title "$title" \
    --arg subtitle "$subtitle" \
    --arg body "$body" \
    --arg sound "$sound" \
    --arg volume "$volume" \
    --arg kind "$kind" \
    '{profile: $profile, openApp: $openApp, title: $title, subtitle: $subtitle, body: $body, sound: $sound, volume: $volume, kind: $kind}' \
    > "$queue_file" 2>/dev/null

  local menubar_pid=""
  [ -f "$pid_file" ] && menubar_pid=$(cat "$pid_file" 2>/dev/null)

  if [ -n "$menubar_pid" ] && kill -0 "$menubar_pid" 2>/dev/null; then
    kill -USR1 "$menubar_pid"
  else
    local args=(--title "$title" --message "$body" --sound "$sound" --volume "$volume")
    [ -n "$subtitle" ] && args+=(--subtitle "$subtitle")
    ( "$NOTIFIER" "${args[@]}" </dev/null >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
  fi
}
