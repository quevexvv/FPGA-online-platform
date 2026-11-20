def frame($segments): reduce $segments[] as $segment (0; . * 128 + $segment);
def windows: [
  frame([6,91,79,102]), frame([91,79,102,109]),
  frame([79,102,109,125]), frame([91,79,102,109])
];
def valid_frame: type == "number" and floor == . and . >= 0 and . < 268435456;
def result($status; $code): {schema_version:1,status:$status,code:$code};
if $uart == [{schema_version:1,uart_status:"board_error"}] then
  result("board_error"; "uart_exchange_failed")
elif $uart == [{schema_version:1,uart_status:"mismatch"}] then
  result("mismatch"; "uart_reply")
elif $uart != [{schema_version:1,uart_status:"passed"}] then
  error("Invalid Lab 3 UART report")
elif . == null then
  result("board_error"; "jtag_trace_unavailable")
elif (.schema_version != 1 or (.current | valid_frame | not) or
      (all(.before,.after; type == "array" and length <= 5 and all(.[]; valid_frame)) | not)) then
  error("Invalid Lab 3 display trace")
else
  windows as $cycle |
  if .current != 0 then result("mismatch"; "display_not_cleared")
  elif .before != ($cycle + [$cycle[0]]) then result("mismatch"; "animation")
  elif (.after as $frames | any(range(4); . as $i |
        $frames == [$cycle[$i],$cycle[($i+1)%4],$cycle[($i+2)%4],
                    $cycle[($i+3)%4],$cycle[$i]] ) | not) then
    result("mismatch"; "animation_after_parity_error")
  else result("passed"; null)
  end
end
