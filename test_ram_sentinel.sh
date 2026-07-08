#!/bin/bash
# Minimal test suite for ram-sentinel.sh (no bats dependency required).
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ram-sentinel.sh"
PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "test: rejects non-numeric threshold"
"$SCRIPT" -t notanumber -o >/dev/null 2>&1
assert_eq "exit code 1" "1" "$?"

echo "test: help exits 0 and prints usage"
out=$("$SCRIPT" -h 2>&1)
code=$?
assert_eq "exit code 0" "0" "$code"
case "$out" in
    *"Usage: ram-sentinel.sh"*) echo "  PASS: usage text present"; PASS=$((PASS+1)) ;;
    *) echo "  FAIL: usage text missing"; FAIL=$((FAIL+1)) ;;
esac

echo "test: forced trigger writes ALERT + top-process log lines"
log="/tmp/ram-sentinel-test-$$.log"
pid="/tmp/ram-sentinel-test-$$.pid"
rm -f "$log" "$pid"
"$SCRIPT" -t 999999999 -n -o -l "$log" -p "$pid" >/dev/null 2>&1
grep -q "\[ALERT\]" "$log"
assert_eq "ALERT line present" "0" "$?"
grep -q "Top memory consumers" "$log"
assert_eq "process table logged" "0" "$?"
rm -f "$log" "$pid"

echo "test: single-instance guard rejects a second run"
log2="/tmp/ram-sentinel-test2-$$.log"
pid2="/tmp/ram-sentinel-test2-$$.pid"
rm -f "$log2" "$pid2"
"$SCRIPT" -t 999999999 -n -l "$log2" -p "$pid2" &
bgpid=$!
sleep 1
"$SCRIPT" -t 999999999 -n -o -l "$log2" -p "$pid2" >/dev/null 2>&1
assert_eq "second instance exit code 2" "2" "$?"
kill "$bgpid" 2>/dev/null
wait "$bgpid" 2>/dev/null
sleep 0.3
[ -f "$pid2" ]
assert_eq "pidfile removed after SIGTERM" "1" "$?"
rm -f "$log2" "$pid2"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
