#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
trap 'chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
export FPGA_JOBS_ROOT="$root/jobs \${literal}"
unset FPGA_DISPATCH_LAUNCH
mkdir -p -- "$root/bin" "$FPGA_JOBS_ROOT/incoming"
export PATH=$root/bin:$PATH

cat > "$root/bin/systemd-run" <<'MANAGER'
#!/usr/bin/env bash
set -euo pipefail
unit=
while [[ $1 != -- ]]; do
    case "$1" in
        --unit=*) unit=${1#--unit=fpga-run-} ;;
        --setenv=*) export "${1#--setenv=}" ;;
        --wait|--pipe|--pty) exit 3 ;;
    esac
    shift
done
shift
[[ -n $unit ]]
job=$FPGA_JOBS_ROOT/runs/$unit
printf '%s\n' "$unit" >> "$FPGA_JOBS_ROOT/launches"
jq -e '.state == "starting" and .started_at == null' "$job/output/status.json" >/dev/null
if [[ ${MANAGER_DOWN:-0} == 1 ]]; then
    echo 'User manager is unavailable' >&2
    exit 1
fi
(
    for _ in {1..200}; do
        [[ ! -f $job/control/release ]] || exec "$@"
        sleep .01
    done
) </dev/null >"$job/manager.log" 2>&1 &
MANAGER
chmod +x -- "$root/bin/systemd-run"

register_input() {
    id=aaaaaaaa-bbbb-cccc-dddd-00000000000$1
    job=$FPGA_JOBS_ROOT/runs/$id
    local upload=$FPGA_JOBS_ROOT/incoming/$id
    mkdir -p -- "$upload/src"
    jq --arg id "$id" '.run_id=$id' examples/manifest.json > "$upload/manifest.json"
    cp -- examples/counter/student_top.v "$upload/src/student_top.v"
}
submit() { bin/fpga-dispatch submit --run-id "$id" --mode mock; }
status() { bin/fpga-dispatch status --run-id "$id"; }

register_input 1
submit | jq -e '.disposition == "accepted"' >/dev/null
status | jq -e '.state == "starting"' >/dev/null
submit | jq -e '.disposition == "existing"' >/dev/null
[[ $(wc -l < "$FPGA_JOBS_ROOT/launches") == 1 ]]
touch -- "$job/control/release"
for _ in {1..100}; do
    state=$(status | jq -er .state)
    [[ $state != finished ]] || break
    sleep .01
done
status | jq -e '.state == "finished" and .result_status == "passed"' >/dev/null
jq -e '.mode == "mock" and .hardware_verified == false' "$job/output/result.json" >/dev/null

register_input 2
MANAGER_DOWN=1 submit 2>"$root/launch-error" | jq -e '.disposition == "accepted"' >/dev/null
grep -q 'User manager is unavailable' "$root/launch-error"
status | jq -e '.state == "finished" and .result_status == "internal_error"' >/dev/null
jq -e --arg kind result -f scripts/contract.jq "$job/output/result.json" >/dev/null
jq -e '.error.code == "service_start_failed" and .started_at == null' "$job/output/result.json" >/dev/null
submit | jq -e '.disposition == "existing"' >/dev/null
[[ $(wc -l < "$FPGA_JOBS_ROOT/launches") == 2 ]]
echo 'PASS: detached dispatch, repeat submit and unavailable user manager'
