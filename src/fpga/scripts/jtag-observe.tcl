proc probe_control {} {
    foreach {source expected} {0 10 1 01 0 10} {
        write_source_data -instance_index 0 -value $source
        set probe [read_probe_data -instance_index 0]
        if {$probe ne $expected} {
            error "JCHK returned $probe after writing $source (expected $expected)"
        }
        puts "JCHK source=$source probe=$probe"
    }
}

proc wait_snapshot_ack {request} {
    set deadline [expr {[clock milliseconds] + 1000}]
    while {[clock milliseconds] < $deadline} {
        set probe [read_probe_data -instance_index 1]
        if {![regexp {^[01]{31}$} $probe]} { error "Invalid SNAP probe value" }
        if {[string index $probe 0] eq $request} { return $probe }
        after 5
    }
    error "Timed out waiting for SNAP acknowledgment"
}

proc capture_snapshot {} {
    # Drain a request left outstanding by an earlier interrupted session.
    set previous [read_source_data -instance_index 1]
    if {![regexp {^[01]$} $previous]} { error "Invalid SNAP source value" }
    wait_snapshot_ack $previous
    set request [expr {1 - $previous}]
    write_source_data -instance_index 1 -value $request
    set acknowledged [wait_snapshot_ack $request]
    set stable [read_probe_data -instance_index 1]
    if {$stable ne $acknowledged} { error "SNAP changed after acknowledgment" }

    scan [string range $stable 1 16] %b state
    scan [string range $stable 17 23] %b hex3
    scan [string range $stable 24 30] %b hex2
    return [format {{"schema_version":1,"state":%d,"hex2":%d,"hex3":%d}} $state $hex2 $hex3]
}

proc observe {mode cable index} {
    switch -- $mode {
        probe { set expected {0 1 2 JCHK}; set action probe_control }
        snapshot { set expected {1 1 31 SNAP}; set action capture_snapshot }
        default { error "Unknown JTAG operation: $mode" }
    }
    if {[lsearch -exact [get_hardware_names] $cable] < 0} {
        error "JTAG cable unavailable: $cable"
    }
    set device [lindex [get_device_names -hardware_name $cable] [expr {$index - 1}]]
    if {$device eq ""} { error "JTAG device index unavailable: $index" }
    set instances [get_insystem_source_probe_instance_info -hardware_name $cable -device_name $device]
    if {[lsearch -exact $instances $expected] < 0} {
        error "Expected JTAG instance ($expected) is missing: $instances"
    }
    start_insystem_source_probe -hardware_name $cable -device_name $device
    set failed [catch {$action} result]
    set close_failed [catch {end_insystem_source_probe} close_message]
    if {$failed} { error $result }
    if {$close_failed} { error $close_message }
    if {$mode eq "snapshot"} { puts "SNAPSHOT $result" }
}

if {[catch {observe {*}$quartus(args)} message]} {
    puts stderr $message
    exit 1
}
