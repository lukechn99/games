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
  # A test that waits on something that never happens fails after 10 min.
  if timeout 600 "$@" >"$log" 2>&1; then
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
    medium) grep -q "^medium checks: 0 failures" "$log" && ! grep -q "SCRIPT ERROR" "$log" ;;
    benchmark) grep -q "^benchmark checks: 0 failures" "$log" && ! grep -q "SCRIPT ERROR" "$log" ;;
    grand-prix) grep -q "^Grand Prix checks: 0 failures" "$log" && ! grep -q "SCRIPT ERROR" "$log" ;;
    intro) grep -q '^intro checks: 0 failures' "$log" && ! grep -q 'SCRIPT ERROR' "$log" ;;
    *) return 0 ;;
  esac
}

summary() {
  case $1 in
    medium) grep -oE "medium checks: [0-9]+ failures" "$log" | tail -1 ;;
    benchmark) grep -oE "benchmark checks: [0-9]+ failures" "$log" | tail -1 ;;
    grand-prix) grep -oE "Grand Prix checks: [0-9]+ failures" "$log" | tail -1 ;;
    intro) grep -oE "intro checks: [0-9]+ failures" "$log" | tail -1 ;;
    game) grep -oE '[0-9]+ passed, [0-9]+ failed' "$log" | tail -1 ;;
    vitest) grep -E 'Tests +[0-9]+' "$log" | sed 's/\x1b\[[0-9;]*m//g; s/^ *//' | tail -1 ;;
    *) echo clean ;;
  esac
}

details() {
  case $1 in
    game|intro|benchmark|medium|grand-prix) grep -E 'FAIL|SCRIPT ERROR|Parse Error|passed, |intro checks|benchmark checks|medium checks|Grand Prix checks' -A1 "$log" ;;
    vitest) sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E 'FAIL|✗|×|Error|expected|Tests ' ;;
    *) cat "$log" ;;
  esac
}

# Godot learns new class_name scripts only on import. A fresh checkout, or
# a pull that adds classes, otherwise fails with "Identifier not declared".
refresh_classes() {
  local cache=racing/.godot/global_script_class_cache.cfg
  if [[ ! -f $cache ]] || [[ -n $(find racing/scripts racing/tests -name '*.gd' -newer "$cache" -print -quit) ]]; then
    "$GODOT" --headless --path racing --import >/dev/null 2>&1
    touch "$cache"
  fi
}

if [[ $what == all || $what == game ]]; then
  refresh_classes
  step game "$GODOT" --headless --path racing --fixed-fps 60 -s tests/run_tests.gd
  step medium "$GODOT" --headless --path racing --fixed-fps 60 -s tests/benchmark_medium.gd
  step benchmark "$GODOT" --headless --path racing --fixed-fps 60 -s tests/benchmark_halves.gd
  step grand-prix "$GODOT" --headless --path racing --fixed-fps 60 -s tests/grand_prix.gd
  step intro "$GODOT" --headless --path racing --fixed-fps 60 -s tests/intro_handoff.gd
fi
if [[ $what == all || $what == site ]]; then
	step browser-tools node --test racing/tools/bench/compare.test.mjs racing/web/mobile.test.mjs racing/web/landscape.test.mjs racing/web/loading.test.mjs
  step vitest npx vitest run --reporter=dot
  step types npx tsc --noEmit
  step lint npx eslint --quiet .
fi
rm -f "$log"
exit $fail
