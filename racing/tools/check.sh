#!/usr/bin/env bash
# Every correctness check, quietly: one line per step when it passes, the
# failures (trimmed) when it doesn't. Run from anywhere:
#   racing/tools/check.sh            game tests + site tests + types + lint
#   racing/tools/check.sh game       just the game tests
#   racing/tools/check.sh site       just the site checks
# Exit status is non-zero if anything failed.
cd "$(dirname "$0")/../.." || exit 2
GODOT="${GODOT:-$HOME/godot/godot}"
what="${1:-all}"
fail=0
log=$(mktemp)

step() {   # name, command...
  local name=$1; shift
  local t0=$SECONDS
  if "$@" >"$log" 2>&1; then
    # Godot may exit zero after a script error before reaching the tests.
    # Match CI: require the final summary and reject script errors too.
    if ! valid_run "$name"; then
      fail=1
      echo "FAIL  $name  (incomplete or errored test run, $((SECONDS - t0)) s)"
      details "$name" | head -40 | sed 's/^/      /'
    else
      echo "ok    $name  ($(summary "$name"), $((SECONDS - t0)) s)"
    fi
  else
    fail=1
    echo "FAIL  $name  ($((SECONDS - t0)) s)"
    details "$name" | head -40 | sed 's/^/      /'
  fi
}

valid_run() {
  case $1 in
    game) grep -qE '^[0-9]+ passed, 0 failed' "$log" && ! grep -q 'SCRIPT ERROR' "$log" ;;
    benchmark) grep -q "^benchmark checks: 0 failures" "$log" && ! grep -q "SCRIPT ERROR" "$log" ;;
    intro) grep -q '^intro checks: 0 failures' "$log" && ! grep -q 'SCRIPT ERROR' "$log" ;;
    *) return 0 ;;
  esac
}

summary() {
  case $1 in
    benchmark) grep -oE "benchmark checks: [0-9]+ failures" "$log" | tail -1 ;;
    intro) grep -oE "intro checks: [0-9]+ failures" "$log" | tail -1 ;;
    game) grep -oE '[0-9]+ passed, [0-9]+ failed' "$log" | tail -1 ;;
    vitest) grep -E 'Tests +[0-9]+' "$log" | sed 's/\x1b\[[0-9;]*m//g; s/^ *//' | tail -1 ;;
    *) echo clean ;;
  esac
}

details() {
  case $1 in
    game|intro|benchmark) grep -E 'FAIL|SCRIPT ERROR|Parse Error|passed, |intro checks|benchmark checks' -A1 "$log" ;;
    vitest) sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E 'FAIL|✗|×|Error|expected|Tests ' ;;
    *) cat "$log" ;;
  esac
}

if [[ $what == all || $what == game ]]; then
  step game "$GODOT" --headless --path racing --fixed-fps 60 -s tests/run_tests.gd
  step benchmark "$GODOT" --headless --path racing --fixed-fps 60 -s tests/benchmark_halves.gd
  step intro "$GODOT" --headless --path racing --fixed-fps 60 -s tests/intro_handoff.gd
fi
if [[ $what == all || $what == site ]]; then
	step browser-tools node --test racing/tools/bench/compare.test.mjs racing/web/mobile.test.mjs racing/web/landscape.test.mjs
  step vitest npx vitest run --reporter=dot
  step types npx tsc --noEmit
  step lint npx eslint --quiet .
fi
rm -f "$log"
exit $fail
