#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
check() { jq -e --arg kind "$1" -f scripts/contract.jq >/dev/null; }
reject() {
    if check "$1"; then echo "FAIL: accepted $2" >&2; exit 1; fi
}
for kind in manifest status result; do
    file="examples/$kind.json"
    check "$kind" < "$file"
    while IFS= read -r key; do
        jq --arg key "$key" 'del(.[$key])' "$file" | reject "$kind" "missing $kind.$key"
    done < <(jq -r 'keys[]' "$file")
    jq '.schema_version = 2' "$file" | reject "$kind" 'incompatible version'
done
check result < examples/result-mock.json
for kind in status result; do
    jq '.mode = "simulation"' "examples/$kind.json" | reject "$kind" 'unknown mode'
done
jq '.hardware_verified = true' examples/result-mock.json | reject result 'verified mock'
jq '.finished_at = "2026-10-30T10:01:00Z"' examples/status.json | reject status 'starting with finish'
jq '.state="running" | .stage="building" | .started_at=.updated_at' examples/status.json | check status
jq '.state="running" | .stage="building" | .started_at="2099-01-01T00:00:00Z"' \
  examples/status.json | reject status 'update before start'
jq '.state="finished" | .stage="finalizing" | .finished_at=.updated_at | .result_status="passed"' examples/status.json | check status
jq '.state="finished" | .stage="finalizing" | .finished_at="2099-01-01T00:00:00Z" | .result_status="passed"' \
  examples/status.json | reject status 'finish after update'
jq '.state="finished" | .stage="finalizing" | .started_at=.updated_at |
  .finished_at="2000-01-01T00:00:00Z" | .result_status="passed"' \
  examples/status.json | reject status 'finish before start'
for value in build_error board_error invalid_input busy internal_error; do
    jq --arg value "$value" '.status=$value | .hardware_verified=false | .started_at=null |
      .summary={planned:1,executed:0,passed:0,failed:0} | .observations=[] |
      .error={stage:"validating",code:$value,message:"Example failure"}' examples/result.json | check result
done
jq '.status="mismatch" | .summary.passed=0 | .summary.failed=1 |
  .observations[0] |= (.expected_dout="0x20003" | .match=false)' examples/result.json | check result
jq '.observations[0] |= (.expected_dout="0x20003" | .mask="0x1ffff")' examples/result.json | check result
jq '.observations[0] |= (.expected_dout="0x3ffff" | .mask="0x00000")' examples/result.json | check result
jq '.status="mismatch" | .summary.passed=0 | .summary.failed=1 |
  .observations[0] |= (.expected_dout="0x20003" | .mask="0x1ffff" | .match=false)' \
  examples/result.json | reject result 'masked outputs agree with match=false'
for filter in '.status="unknown"' '.summary.executed=2' '.logs=["../outside"]' \
    '.hardware_verified=false' '.observations[0].din="0x400"' '.observations[0].match=false' \
    '.observations[0].expected_dout="0x20003"' '.observations[0].unexpected=0' \
    '.finished_at="2026-10-30T10:00:00Z"'; do
    jq "$filter" examples/result.json | reject result "$filter"
done
jq '.summary={planned:2,executed:2,passed:2,failed:0} | .observations += .observations' \
  examples/result.json | reject result 'duplicate observation index'
for filter in '.sources=["../escape.v"]' '.sources=[]' '.top="wrong"'; do
    jq "$filter" examples/manifest.json | reject manifest "$filter"
done
echo 'PASS: contract fixtures, required fields, seven statuses and negative cases'
