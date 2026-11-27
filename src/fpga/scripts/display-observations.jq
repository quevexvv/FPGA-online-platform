include "output-match" {search:"./"};

def led_bits($first; $end):
  . as $value | [range($first; $end) | ($value / pow(2; .) | floor % 2 == 1)];

def led_observations:
  if (.mode != "hardware" and .mode != "mock") or (.hardware_verified | type != "boolean") or
     (.mode == "mock" and .hardware_verified) or (.observations | type != "array") or
     (all(.observations[]; .dout | type == "string" and test("\\A0x[0-3][0-9a-f]{4}\\z")) | not)
  then error("Invalid LED observations")
  else {schema_version, run_id, mode, status, hardware_verified,
    observations: [.observations[] | {vector_index} + (.dout | hex |
      {red: led_bits(0; 10), green: led_bits(10; 18)})]}
  end;

def valid_frame: type == "number" and floor == . and . >= 0 and . < 268435456;
def digits: . as $frame | [range(4) | $frame / pow(128; .) | floor % 128];
def lab3_observations:
  if (.current | valid_frame | not) or
     (all(.before, .after; type == "array" and length <= 5 and all(.[]; valid_frame)) | not)
  then error("Invalid Lab 3 display trace")
  else {schema_version, current: (.current | digits), before: (.before | map(digits)),
    after: (.after | map(digits))}
  end;

if .schema_version != 1 then error("Unsupported observation version")
elif $source == "led" then led_observations
elif $source == "lab3" then lab3_observations
else error("Expected observation source: led or lab3")
end
