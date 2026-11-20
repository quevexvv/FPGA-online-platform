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

proc observe {mode cable index} {
    if {[lsearch -exact [get_hardware_names] $cable] < 0} {
        error "JTAG cable unavailable: $cable"
    }
    set device [lindex [get_device_names -hardware_name $cable] [expr {$index - 1}]]
    if {$device eq ""} { error "JTAG device index unavailable: $index" }
    set instances [get_insystem_source_probe_instance_info -hardware_name $cable -device_name $device]
    if {[lsearch -exact $instances {0 1 2 JCHK}] < 0} {
        error "Expected JCHK instance is missing: $instances"
    }
    start_insystem_source_probe -hardware_name $cable -device_name $device
    set failed [catch {probe_control} message]
    set close_failed [catch {end_insystem_source_probe} close_message]
    if {$failed} { error $message }
    if {$close_failed} { error $close_message }
}

if {[catch {observe {*}$quartus(args)} message]} {
    puts stderr $message
    exit 1
}
