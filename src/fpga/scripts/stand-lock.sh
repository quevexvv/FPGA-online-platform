# shellcheck shell=bash
# shellcheck disable=SC2034

# Keep this descriptor open for the lifetime of the hardware operation.
open_hardware_stand_lock() {
    local account operator_uid operator_home home_info home_owner home_mode lock_path
    hardware_lock_error='Cannot look up the stand operator'
    account=$(getent passwd "$EUID") || return 1
    IFS=: read -r _ _ operator_uid _ _ operator_home _ <<< "$account"
    hardware_lock_error='Stand operator home is invalid'
    [[ $operator_uid == "$EUID" && $operator_home == /* && $operator_home != / &&
        -d $operator_home ]] || return 1
    hardware_lock_error='Cannot inspect the stand operator home'
    home_info=$(stat -Lc '%u %a' -- "$operator_home") || return 1
    read -r home_owner home_mode <<< "$home_info"
    hardware_lock_error='Stand operator home is unsafe'
    [[ $home_owner == "$EUID" && $home_mode =~ ^[0-7]{3,4}$ ]] &&
        (( (8#$home_mode & 022) == 0 )) || return 1
    lock_path=$operator_home/.fpga-stand-lock
    mkdir -m 700 -- "$lock_path" 2>/dev/null || :
    hardware_lock_error='Cannot open a private stand lock directory'
    [[ -d $lock_path && ! -L $lock_path &&
        $(stat -c '%u %a' -- "$lock_path") == "$EUID 700" ]] || return 1
    exec {stand_lock}< "$lock_path"
}
