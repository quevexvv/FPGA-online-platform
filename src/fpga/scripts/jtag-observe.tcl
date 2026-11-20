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

proc wait_snapshot_ack {index width request} {
    set deadline [expr {[clock milliseconds] + 1000}]
    while {[clock milliseconds] < $deadline} {
        set probe [read_probe_data -instance_index $index]
        if {[string length $probe] != $width || ![regexp {^[01]+$} $probe]} {
            error "Invalid SNAP probe value"
        }
        if {[string index $probe 0] eq $request} { return $probe }
        after 5
    }
    error "Timed out waiting for SNAP acknowledgment"
}

proc capture_snapshot_bits {index width} {
    # Drain a request left outstanding by an earlier interrupted session.
    set previous [read_source_data -instance_index $index]
    if {![regexp {^[01]$} $previous]} { error "Invalid SNAP source value" }
    wait_snapshot_ack $index $width $previous
    set request [expr {1 - $previous}]
    write_source_data -instance_index $index -value $request
    set acknowledged [wait_snapshot_ack $index $width $request]
    set stable [read_probe_data -instance_index $index]
    if {$stable ne $acknowledged} { error "SNAP changed after acknowledgment" }
    return $stable
}

proc capture_snapshot {} {
    set stable [capture_snapshot_bits 1 31]
    scan [string range $stable 1 16] %b state
    scan [string range $stable 17 23] %b hex3
    scan [string range $stable 24 30] %b hex2
    return [format {{"schema_version":1,"state":%d,"hex2":%d,"hex3":%d}} $state $hex2 $hex3]
}

proc trace_frames {bits start count} {
    if {$count > 5} { error "Invalid Lab 3 trace count" }
    set frames {}
    for {set i [expr {5 - $count}]} {$i < 5} {incr i} {
        set first [expr {$start + $i * 28}]
        scan [string range $bits $first [expr {$first + 27}]] %b frame
        lappend frames $frame
    }
    return [join $frames ,]
}

proc capture_lab3_trace {} {
    set bits [capture_snapshot_bits 0 315]
    scan [string range $bits 1 3] %b before_count
    scan [string range $bits 4 6] %b after_count
    scan [string range $bits 7 34] %b current
    return [format {{"schema_version":1,"current":%d,"before":[%s],"after":[%s]}} \
        $current [trace_frames $bits 35 $before_count] [trace_frames $bits 175 $after_count]]
}

proc observe {mode cable index} {
    switch -- $mode {
        probe { set expected {0 1 2 JCHK}; set action probe_control }
        snapshot { set expected {1 1 31 SNAP}; set action capture_snapshot }
        lab3-trace { set expected {0 1 315 L3TR}; set action capture_lab3_trace }
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
    if {$mode ne "probe"} { puts "SNAPSHOT $result" }
}

if {[catch {observe {*}$quartus(args)} message]} {
    puts stderr $message
    exit 1
}
