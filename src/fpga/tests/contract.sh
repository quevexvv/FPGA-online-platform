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
jq '.state="finished" | .stage="finalizing" | .finished_at=.updated_at | .result_status="passed"' examples/status.json | check status
for value in build_error board_error invalid_input busy internal_error; do
    jq --arg value "$value" '.status=$value | .hardware_verified=false | .started_at=null |
      .summary={planned:1,executed:0,passed:0,failed:0} | .observations=[] |
      .error={stage:"validating",code:$value,message:"Example failure"}' examples/result.json | check result
done
jq '.status="mismatch" | .summary.passed=0 | .summary.failed=1 |
  .observations[0].match=false' examples/result.json | check result
for filter in '.status="unknown"' '.summary.executed=2' '.logs=["../outside"]' \
    '.hardware_verified=false' '.observations[0].din="0x400"' '.observations[0].match=false'; do
    jq "$filter" examples/result.json | reject result "$filter"
done
for filter in '.sources=["../escape.v"]' '.sources=[]' '.top="wrong"'; do
    jq "$filter" examples/manifest.json | reject manifest "$filter"
done
echo 'PASS: contract fixtures, required fields, seven statuses and negative cases'
