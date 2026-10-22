#!/usr/bin/env bash
# Isolated CLI-output regressions: no WordPress, database, ICP network or identity access.
source "$(dirname "$0")/lib.sh"
section "WordPress fixture IDs and plugin diagnostics"
fixture_wp() { printf '%s\n' "$fixture_output"; return "$fixture_status"; }
# shellcheck disable=SC2034  # consumed by the sourced wp_ids helper
W=fixture_wp; fixture_status=0
LOG="$WORK/wp-cli-output-check.log"
fixture_output=12
assert_eq "one ID" "$(wp_id 2>"$LOG")" "12"
fixture_output=$'12\n27'
assert_eq "multiple IDs become scoped CSV" "$(wp_ids 2>"$LOG")" "12,27"
fixture_output=$'plugin notice before\n12\nplugin notice between\n27\nplugin notice after'
assert_eq "notices do not enter ID list" "$(wp_ids 2>"$LOG")" "12,27"
assert_contains "notice before remains visible" "$(cat "$LOG")" "plugin notice before"
assert_contains "notice between remains visible" "$(cat "$LOG")" "plugin notice between"
assert_contains "notice after remains visible" "$(cat "$LOG")" "plugin notice after"
fixture_output=$'12\nplugin notice after'
assert_eq "single-ID wrapper retains notices" "$(wp_id 2>"$LOG")" "12"
assert_contains "single-ID diagnostic remains visible" "$(cat "$LOG")" "plugin notice after"
for fixture_output in '' 'plugin notice only' '0' '-4' $'12\n12'; do
  if wp_ids >"$LOG" 2>&1; then fail "invalid or duplicate scope rejected"; else ok "invalid or duplicate scope rejected"; fi
done
fixture_output=$'12\n27'
if wp_id >"$LOG" 2>&1; then fail "single-ID wrapper rejects ambiguity"; else ok "single-ID wrapper rejects ambiguity"; fi
fixture_status=37; fixture_output=12
status=0; wp_ids >"$LOG" 2>&1 || status=$?
assert_eq "ID-list command failure retained" "$status" "37"
status=0; wp_id >"$LOG" 2>&1 || status=$?
assert_eq "single-ID command failure retained" "$status" "37"
summary
