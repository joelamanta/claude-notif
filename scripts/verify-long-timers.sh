#!/usr/bin/env bash
# Verify long-running timer cancel logic for cursor/codex/claude hooks.
set -euo pipefail

failures=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }

test_profile() {
  local profile="$1"
  local config_file="/tmp/noto-verify-${profile}.json"
  local queue="/tmp/noto-${profile}-pending-verify.json"

  printf '{"enabled":true,"%s":{"enabled":true,"enableLongRunning":true,"longRunningThresholds":[1]}}\n' "$profile" > "$config_file"

  NOTIF_PROFILE="$profile" CONFIG_FILE="$config_file" NOTIFIER=/bin/echo \
    bash -c "source \"$HOME/.cursor/hooks/read-config.sh\"; cancel_long_timers \"$profile\"; start_long_timers \"$profile\" test-session \"$queue\" Test '.${profile}.longRunningThresholds // [1] | .[]'"

  local active="/tmp/${profile}-longtimer-active"
  local pid_file="/tmp/${profile}-longtimer-1.pid"

  [ -f "$active" ] || fail "$profile active marker missing" && pass "$profile active marker set"
  [ -f "$pid_file" ] || fail "$profile pid file missing" && pass "$profile pid file set"

  local pid
  pid=$(cat "$pid_file")
  kill -0 "$pid" 2>/dev/null || fail "$profile timer process not running"

  NOTIF_PROFILE="$profile" CONFIG_FILE="$config_file" NOTIFIER=/bin/echo \
    bash -c "source \"$HOME/.cursor/hooks/read-config.sh\"; finish_long_timers \"$profile\""

  [ ! -f "$active" ] || fail "$profile active marker still present after finish"
  [ ! -f "$pid_file" ] || fail "$profile pid file still present after finish"
  kill -0 "$pid" 2>/dev/null && fail "$profile timer process still alive after finish"

  pass "$profile timers cancelled on finish"

  rm -f "$config_file" "$queue" "$active" "$pid_file" /tmp/${profile}-longtimer-*.pid 2>/dev/null || true
}

for profile in cursor codex claude; do
  test_profile "$profile"
done

# Hook ordering: completion hooks must cancel before notifier guard.
for hook in \
  "$HOME/.cursor/hooks/after-agent-response.sh" \
  "$HOME/.cursor/hooks/stop.sh" \
  "$HOME/.codex/hooks/stop.sh" \
  "$HOME/.claude/hooks/noto-stop.sh"; do
  if grep -q 'finish_long_timers' "$hook" && \
     awk '/finish_long_timers/{f=NR} /\[ -x "\$NOTIFIER" \]/{n=NR} END{exit !(f && n && f < n)}' "$hook"; then
    pass "$(basename "$hook") cancels before notifier guard"
  else
    fail "$(basename "$hook") cancel order"
  fi
done

if [ "$failures" -eq 0 ]; then
  printf '\nAll long-running timer checks passed.\n'
  exit 0
fi

printf '\n%d check(s) failed.\n' "$failures"
exit 1
