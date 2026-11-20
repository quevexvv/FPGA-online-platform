# shellcheck shell=bash
# The caller holds the registration and activity locks for this run.
reconcile_run() {
    local run=$1 id=$2 mode=$3 contract=$4
    local output=$run/output state stage started result_status updated status_finished
    local code message fields launch registered_boot current_boot active
    optional_file "$output/result.json" || return 1
    fields=$(jq -ers --arg id "$id" --arg mode "$mode" '
        select(length == 1) | .[0] |
        select(.schema_version == 1 and .run_id == $id and .mode == $mode
            and (.state == "starting" or .state == "running" or .state == "finished")) |
        [.state, .stage, (.started_at // "-"), (.result_status // "-"), .updated_at,
         (.finished_at | strings // "-")] | @tsv
    ' "$output/status.json") || return 1
    IFS=$'\t' read -r state stage started result_status updated status_finished <<< "$fields"
    [[ $started != - ]] || started=

    if safe_file "$output/result.json"; then
        if jq -e --arg kind result -f "$contract" "$output/result.json" >/dev/null &&
           fields=$(jq -ers --arg id "$id" --arg mode "$mode" '
               select(length == 1) | .[0] | select(.run_id == $id and .mode == $mode) |
               [.status, (.started_at // "-"), .finished_at] | @tsv
           ' "$output/result.json"); then
            local final_status final_started finished
            IFS=$'\t' read -r final_status final_started finished <<< "$fields"
            [[ $final_started != - ]] || final_started=
            if [[ $state != finished || $stage != finalizing || $result_status != "$final_status" ||
                  $started != "$final_started" || $status_finished != "$finished" ||
                  $updated != "$finished" ]]; then
                publish_run_status "$output" "$id" "$mode" "$final_started" \
                    finished finalizing "$final_status" "$finished" || return 1
            fi
            return 0
        fi
        code=result_invalid
        message='Published result is invalid'
    elif [[ $state == finished ]]; then
        code=result_missing
        message='Finished run has no result'
    else
        launch=manual
        registered_boot=
        optional_file "$run/control/launch.json" || return 1
        if exists "$run/control/launch.json"; then
            fields=$(jq -ers '
                select(length == 1) | .[0] | select(.launch == "manual" or .launch == "systemd") |
                select(.boot_id | type == "string" and test("^[0-9a-f-]{36}$")) |
                [.launch, .boot_id] | @tsv
            ' "$run/control/launch.json") || return 1
            IFS=$'\t' read -r launch registered_boot <<< "$fields"
        fi
        read -r current_boot < /proc/sys/kernel/random/boot_id || return 1
        if [[ -n $registered_boot && $registered_boot != "$current_boot" ]]; then
            code=host_restarted
            message='Host restarted before the run finished'
        elif [[ $state == running || -d $run/control/started ]]; then
            code=interrupted
            message='Executor exited before publishing a result'
        elif [[ $launch == systemd ]]; then
            active=$(systemctl --user show --property=ActiveState --value "fpga-run-$id.service") ||
                return 1
            case "$active" in
                inactive|failed)
                    code=service_start_failed
                    message='FPGA user service did not start the executor'
                    ;;
                *) return 0 ;;
            esac
        else
            return 0
        fi
    fi
    publish_run_result "$output" "$id" "$mode" "$started" internal_error "$stage" "$code" "$message"
}
