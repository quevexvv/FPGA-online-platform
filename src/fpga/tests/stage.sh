#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
supervisor=
cleanup() {
    if [[ -n $supervisor ]]; then
        kill -TERM "$supervisor" 2>/dev/null || :
        wait "$supervisor" || :
    fi
    rm -rf -- "$root"
}
trap cleanup EXIT

stage() { ./build/fpga-stage "$@"; }
expect_exit() {
    local expected=$1 code=0
    shift
    "$@" || code=$?
    if [[ $code != "$expected" ]]; then
        printf 'FAIL: expected stage exit %s, got %s\n' "$expected" "$code" >&2
        exit 1
    fi
}
wait_ready() {
    for _ in {1..200}; do
        [[ -s $1 ]] && return
        sleep .01
    done
    echo 'FAIL: test process did not start' >&2
    exit 1
}

# shellcheck disable=SC2016
stage 2000 1024 "$root/log with spaces" -- /bin/bash -c 'printf "%s\n" "$1"; echo stderr >&2' _ 'two words'
diff -u <(printf 'two words\nstderr\n') "$root/log with spaces"
expect_exit 125 stage 2000 10 "$root/log with spaces" -- /bin/true
expect_exit 1 stage 2000 100 "$root/exit.log" -- /bin/bash -c 'exit 124'
stage 2000 128 "$root/large.log" -- /bin/head -c 1048576 /dev/zero
[[ $(wc -c < "$root/large.log") -eq 128 ]]

cat > "$root/tree" <<'TREE'
#!/usr/bin/env bash
trap '' TERM
setsid /bin/bash -c 'trap "" TERM; echo "$$" > "$1"; exec sleep 30' _ "$1" &
wait
TREE
expect_exit 124 stage 1000 128 "$root/timeout.log" -- /bin/bash "$root/tree" "$root/timed-child"
[[ -s $root/timed-child ]]
! kill -0 "$(<"$root/timed-child")" 2>/dev/null || exit 1

./build/fpga-stage 10000 128 "$root/signal.log" -- /bin/bash "$root/tree" "$root/stopped-child" &
supervisor=$!
wait_ready "$root/stopped-child"
kill -TERM "$supervisor"
expect_exit 143 wait "$supervisor"
supervisor=
! kill -0 "$(<"$root/stopped-child")" 2>/dev/null || exit 1
echo 'PASS: stage arguments, log cap, timeout and descendant shutdown'
