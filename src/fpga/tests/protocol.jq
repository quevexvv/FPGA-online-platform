# Table checker for complete request frames, not a streaming UART parser.
def classify:
  if (endswith("\n") | not) then "incomplete"
  elif length != 7 then "E2"
  elif .[0:1] != "1" then "E1"
  elif (.[1:2] | IN("R","I","S","Q") | not) then "E3"
  elif (.[2:6] | test("^[0-9a-f]{4}$") | not) then "E2"
  elif (.[1:2] == "R" or .[1:2] == "Q") and .[2:6] != "0000" then "E4"
  elif .[1:2] == "I" and (.[2:6] | test("^0[0-3][0-9a-f]{2}$") | not) then "E4"
  else "ok" end;
def response:
  if length == 8 and test("^1(K00000|D[0-3][0-9a-f]{4}|E0000[1-6])\n$") then "ok" else "invalid" end;
length == 30 and all(.[];
  (if .direction == "response" then (.frame | response) else (.frame | classify) end) == .classification)
