#!/bin/zsh
# Runs the tests with hard time limits, so a stuck test can never hang a
# build (Dylan, 2026-11-20: "make sure you add a timeout so they dont hang").
#
#   scripts/test.sh unit            # JarvisKit tests, 5 minutes at most
#   scripts/test.sh ui [Test ...]   # UI tests on a simulator, 15 minutes at most
#
# Each UI test also has its own allowance (3 minutes, 4 at the very most):
# a test past it fails, naming itself, and the run carries on. The whole run
# past its limit is stopped, and the test that was in flight is named.
# SIMULATOR picks the simulator (a name or UDID); the default is the iPhone
# 18 Pro Max this project tests on.
set -u
cd "${0:A:h}/.."

UNIT_LIMIT=300
UI_LIMIT=900
SIMULATOR=${SIMULATOR:-3F872A85-C44D-419E-9E7C-5A1805B9B4B3}
LOG=${TMPDIR:-/tmp}/jarvis-tests.log

case "${1:-}" in
unit)
    timeout $UNIT_LIMIT swift test 2>&1 | tee "$LOG" | grep -E "error:|Executed .* tests" | tail -3
    code=${pipestatus[1]}
    ;;
ui)
    shift
    only=()
    for name in "$@"; do only+=(-only-testing:JarvisUITests/$name); done
    timeout $UI_LIMIT xcodebuild test -scheme Jarvis -destination "id=$SIMULATOR" \
        -derivedDataPath build/uit -disableAutomaticPackageResolution -skipPackageUpdates \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 180 \
        -maximum-test-execution-time-allowance 240 \
        "${only[@]}" > "$LOG" 2>&1
    code=$?
    grep -E "Test Case.*(passed|failed)|\*\* TEST|exceeded" "$LOG" | sed -E 's/^.*\[JarvisUITests\.//; s/\]//'
    ;;
*)
    echo "usage: scripts/test.sh unit | ui [TestClass ...]" >&2
    exit 2
    ;;
esac

# `timeout` answers 124 when it had to stop the run.
if [[ $code == 124 ]]; then
    echo "STOPPED: over the time limit." >&2
    inflight=$(grep -E "Test Case .* started" "$LOG" | tail -1)
    [[ -n $inflight ]] && echo "In flight: $inflight" >&2
fi
echo "Full log: $LOG"
exit $code
