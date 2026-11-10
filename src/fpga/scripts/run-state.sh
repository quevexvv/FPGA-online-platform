# shellcheck shell=bash

timestamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

write_run_json() {
    local destination=$1 temporary
    shift
    temporary=$(mktemp -- "${destination%/*}/.json.XXXXXXXX") || return 1
    if ! jq -cn "$@" > "$temporary" || ! mv -T -- "$temporary" "$destination"; then
        rm -f -- "$temporary"
        printf 'Cannot publish %s\n' "$destination" >&2
        return 1
    fi
}

publish_run_status() {
    local output=$1 id=$2 mode=$3 started=$4 state=$5 stage=$6 result=${7:-} now
    now=${8:-}
    if [[ -z $now ]]; then now=$(timestamp) || return 1; fi
    # shellcheck disable=SC2016
    write_run_json "$output/status.json" --arg id "$id" --arg mode "$mode" \
        --arg started "$started" --arg state "$state" --arg stage "$stage" \
        --arg result "$result" --arg now "$now" '
        {schema_version:1,run_id:$id,mode:$mode,state:$state,stage:$stage,
         started_at:($started | select(length>0) // null),updated_at:$now,
         finished_at:(if $state == "finished" then $now else null end),
         result_status:($result | select(length>0) // null)}'
}

publish_run_result() {
    local output=$1 id=$2 mode=$3 started=$4 result=$5 stage=$6 code=$7 message=$8
    local planned=${9:-0} comparison=${10:-/dev/null} now log logs
    local log_files=()
    now=$(timestamp) || return 1
    for log in logs/{build,program,uart,test}.log; do
        if [[ -f $output/$log && ! -L $output/$log ]]; then log_files+=("$log"); fi
    done
    logs=$(jq -cn --args '$ARGS.positional' "${log_files[@]}") || return 1
    # shellcheck disable=SC2016
    write_run_json "$output/result.json" --arg id "$id" --arg mode "$mode" --arg result "$result" \
        --arg started "$started" --arg now "$now" --arg stage "$stage" --arg code "$code" \
        --arg message "$message" --argjson logs "$logs" --argjson planned "$planned" \
        --slurpfile comparison "$comparison" '
        {schema_version:1,run_id:$id,mode:$mode,status:$result,
         hardware_verified:($mode == "hardware" and ($result == "passed" or $result == "mismatch")),
         started_at:($started | select(length>0) // null),finished_at:$now,
         error:(if $code == "" then null else {stage:$stage,code:$code,message:$message} end),logs:$logs}
        + ($comparison[0] // {summary:{planned:$planned,executed:0,passed:0,failed:0},observations:[]})' ||
        return 1
    publish_run_status "$output" "$id" "$mode" "$started" finished finalizing "$result" "$now"
}
