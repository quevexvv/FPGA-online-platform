#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
trap 'chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
export FPGA_JOBS_ROOT=$root/'jobs root'
mkdir -p -- "$FPGA_JOBS_ROOT/incoming"
incoming=$FPGA_JOBS_ROOT/incoming
runs=$FPGA_JOBS_ROOT/runs
id=$(jq -r '.run_id' examples/manifest.json)

upload() {
    mkdir -p -- "$incoming/$1/src"
    jq --arg id "$1" '.run_id=$id' examples/manifest.json > "$incoming/$1/manifest.json"
    cp -- examples/counter/student_top.v "$incoming/$1/src/student_top.v"
}
submit() { bin/fpga-dispatch submit --run-id "$1" --mode "$2"; }
status() { bin/fpga-dispatch status --run-id "$1"; }
reject() {
    local expected=$1 code=0
    shift
    "$@" > "$root/rejected.json" 2> "$root/rejected.log" || code=$?
    if [[ $code != "$expected" || -s $root/rejected.json ]]; then
        printf 'FAIL: expected exit %s with no response, got %s (%s)\n' "$expected" "$code" "$*" >&2
        exit 1
    fi
}

reject 2 submit '../unsafe' hardware
reject 2 status "$id"
reject 2 submit "$id" hardware
upload "$id"
submit "$id" hardware > "$root/first.json" & first=$!
submit "$id" hardware > "$root/second.json" & second=$!
wait "$first"
wait "$second"
jq -es --arg id "$id" '
    all(.[]; .schema_version == 1 and .run_id == $id) and
    (map(.disposition) | sort) == ["accepted","existing"]
' "$root/first.json" "$root/second.json" >/dev/null
[[ ! -e $incoming/$id ]]
cmp examples/counter/student_top.v "$runs/$id/input/src/student_top.v"
[[ $(stat -c %a -- "$runs/$id/input/src/student_top.v") == 400 ]]
status "$id" | jq -e --arg id "$id" '
    .run_id == $id and .mode == "hardware" and .state == "starting" and .stage == "dispatch"
' >/dev/null
status "$id" | jq -e --arg kind status -f scripts/contract.jq >/dev/null
submit "$id" hardware | jq -e '.disposition == "existing"' >/dev/null
reject 2 submit "$id" mock
upload "$id"
reject 2 submit "$id" hardware
[[ -d $incoming/$id ]]

partial=aaaaaaaa-bbbb-cccc-dddd-000000000001
mkdir -- "$incoming/$partial"
reject 2 submit "$partial" hardware
grep -q 'invalid_input' "$root/rejected.log"
[[ -d $incoming/$partial && ! -e $runs/$partial && ! -e $runs/.$partial.pending ]]
upload "$partial"
chmod u-w -- "$incoming/$partial/src"
submit "$partial" mock >/dev/null
status "$partial" | jq -e '.mode == "mock"' >/dev/null

symlink=aaaaaaaa-bbbb-cccc-dddd-000000000004
ln -s -- "$runs/$id/input" "$incoming/$symlink"
reject 2 submit "$symlink" hardware
[[ -L $incoming/$symlink && ! -e $runs/$symlink ]]

interrupted=aaaaaaaa-bbbb-cccc-dddd-000000000002
upload "$interrupted"
mkdir -p -- "$runs/.$interrupted.pending/ready/work"
mv -- "$incoming/$interrupted" "$runs/.$interrupted.pending/upload"
submit "$interrupted" hardware > /dev/null
submit "$interrupted" hardware | jq -e '.disposition == "existing"' >/dev/null

mkdir -- "$root/fake"
export REAL_JQ REAL_MV
REAL_JQ=$(command -v jq)
REAL_MV=$(command -v mv)
cat > "$root/fake/jq" <<'FAKE_JQ'
#!/usr/bin/env bash
[[ $* != *'state:"starting"'* ]] || exit 1
exec "$REAL_JQ" "$@"
FAKE_JQ
cat > "$root/fake/mv" <<'FAKE_MV'
#!/usr/bin/env bash
[[ $* != *'.pending/ready '* ]] || exit 1
exec "$REAL_MV" "$@"
FAKE_MV
failure=aaaaaaaa-bbbb-cccc-dddd-000000000003
upload "$failure"
for tool in jq mv; do
    chmod +x -- "$root/fake/$tool"
    PATH="$root/fake:$PATH" reject 1 submit "$failure" hardware
    chmod -x -- "$root/fake/$tool"
    [[ -f $incoming/$failure/manifest.json && ! -e $runs/$failure && ! -e $runs/.$failure.pending ]]
    reject 2 status "$failure"
done
submit "$failure" hardware | jq -e '.disposition == "accepted"' >/dev/null
echo 'PASS: submit, status, concurrent retry and registration rollback'
