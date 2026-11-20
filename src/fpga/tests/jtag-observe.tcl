proc get_hardware_names {} { return {test-cable} }
proc get_device_names {args} { return {test-device} }
proc get_insystem_source_probe_instance_info {args} { return {{1 1 31 SNAP}} }
proc start_insystem_source_probe {args} { incr ::opened }
proc end_insystem_source_probe {} { incr ::closed }
proc read_source_data {args} { return 1 }
proc write_source_data {args} { lappend ::writes [lindex $args end] }
proc read_probe_data {args} {
    set probe [lindex $::replies 0]
    if {[llength $::replies] > 1} { set ::replies [lrange $::replies 1 end] }
    return $probe
}

set opened 0
set closed 0
set writes {}
set previous 1000000000000000000000000000000
# New acknowledgment, state 0x002a, HEX3=0x5b and HEX2=0x77.
set captured 0000000000010101010110111110111
set replies [list $previous $previous $captured $captured]
set quartus(args) {snapshot test-cable 1}
source [file join [file dirname [info script]] .. scripts jtag-observe.tcl]
if {$opened != 1 || $closed != 1 || $writes ne "0"} {
    error "Expected exactly one acknowledged request and a closed session"
}

set replies [list $previous $captured $captured]
set expected {{"schema_version":1,"state":42,"hex2":119,"hex3":91}}
if {[capture_snapshot] ne $expected} { error "Unexpected snapshot bit layout" }

foreach {replies expected} [list \
    [list $previous] "Timed out waiting for SNAP acknowledgment" \
    [list $previous $captured $previous] "SNAP changed after acknowledgment" \
    [list invalid] "Invalid SNAP probe value"] {
    if {![catch {observe snapshot test-cable 1} error] || $error ne $expected} {
        error "Expected snapshot error: $expected"
    }
    if {$opened != $closed} { error "Expected session cleanup after failure" }
}
puts "PASS: decoded snapshot, timeout, unstable/invalid data and session cleanup"

set previous "1[string repeat 0 314]"
set one "[string repeat 0 27]1"
set two "[string repeat 0 26]10"
set captured "0010001${one}[string repeat 0 84]${one}${two}[string repeat 0 112]${two}"
set replies [list $previous $captured $captured]
set expected {{"schema_version":1,"current":1,"before":[1,2],"after":[2]}}
if {[capture_lab3_trace] ne $expected} { error "Unexpected Lab 3 trace bit layout" }
puts "PASS: wide JTAG trace decoding and frame order"
