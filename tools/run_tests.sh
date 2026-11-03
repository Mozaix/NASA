#!/bin/bash
# Runs the test suite. Passes only if every check passes AND no script or engine error was printed,
# because a script error aborts a test function without counting as a failed check.
cd "$(dirname "$0")/.."
OUT="$(godot --headless --path . res://tests/run_tests.tscn 2>&1)"
echo "$OUT" | grep -E '^  (gale|valles|shackleton|physics|land |Mars windows)|PASSED|FAIL:' | cut -c1-170
ERRS="$(echo "$OUT" | grep -E 'SCRIPT ERROR|^ERROR|^WARNING|Parse Error' | sort -u | cut -c1-200)"
if [ -n "$ERRS" ]; then echo "--- errors and warnings:"; echo "$OUT" | grep -E -A2 'SCRIPT ERROR|^ERROR|^WARNING|Parse Error' | cut -c1-200 | awk '!s[$0]++' | head -30; echo "RESULT: FAILED (errors above)"; exit 1; fi
if echo "$OUT" | grep -q 'FAILED 0'; then echo "RESULT: OK"; exit 0; fi
echo "RESULT: FAILED"; exit 1
