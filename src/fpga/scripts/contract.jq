# Example validation only; filesystem containment is checked by the dispatcher.
def required($keys): . as $obj | type == "object" and all($keys[]; . as $k | $obj | has($k));
def member($values): . as $v | $values | index($v) != null;
def uuid: type == "string" and test("^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$");
def utc: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def maybe_time: . == null or utc;
def natural: type == "number" and . >= 0 and floor == .;
def relative: type == "string" and test("^[A-Za-z0-9_-][A-Za-z0-9_./-]*$")
  and (split("/") | all(. != ".." and . != "." and . != ""));
def final_status: member(["passed","mismatch","build_error","board_error","invalid_input","busy","internal_error"]);
def stage: member(["dispatch","validating","locking","building","programming","testing","finalizing"]);
def common: required(["schema_version","run_id"]) and .schema_version == 1 and (.run_id | uuid);
def mode: .mode | member(["hardware","mock"]);
def manifest:
  required(["top","kind","sources","test_set"]) and .top == "student_top"
  and (.kind | member(["combinational","sequential"]))
  and (.sources | type == "array" and length > 0 and all(.[]; relative and endswith(".v")))
  and (.test_set | type == "string" and test("^[A-Za-z0-9_-]+$"));
def status:
  required(["mode","state","stage","started_at","updated_at","finished_at","result_status"])
  and mode and (.stage | stage) and (.updated_at | utc) and (.started_at | maybe_time)
  and (if .state == "starting" then .stage == "dispatch" and .started_at == null
       and .finished_at == null and .result_status == null
    elif .state == "running" then (.started_at | utc) and .finished_at == null and .result_status == null
    elif .state == "finished" then .stage == "finalizing" and (.finished_at | utc)
       and (.result_status | final_status) else false end);
def summary:
  required(["planned","executed","passed","failed"])
  and all(.[]; natural) and .executed <= .planned and .passed + .failed == .executed;
def observation:
  required(["vector_index","din","steps","dout","expected_dout","mask","match"])
  and (.vector_index | natural) and (.steps | natural) and (.match | type == "boolean")
  and (.din | type == "string" and test("^0x[0-3][0-9a-f]{2}$"))
  and all(.dout,.expected_dout,.mask; type == "string" and test("^0x[0-3][0-9a-f]{4}$"));
def result:
  required(["mode","status","hardware_verified","started_at","finished_at","summary","observations","error","logs"])
  and mode and (.status | final_status) and (.hardware_verified | type == "boolean")
  and (if .mode == "mock" then .hardware_verified == false else true end)
  and (.started_at | maybe_time) and (.finished_at | utc) and (.summary | summary)
  and (.observations | type == "array" and all(.[]; observation))
  and (.observations | length) == .summary.executed
  and ([.observations[] | select(.match)] | length) == .summary.passed
  and (.logs | type == "array" and all(.[]; relative))
  and (.error == null or (.error | required(["stage","code","message"])
       and (.stage | stage) and (.code | type == "string") and (.message | type == "string")))
  and (if .status == "passed" or .status == "mismatch" then
       .error == null and (.started_at | utc) and .summary.executed == .summary.planned
       and (if .mode == "hardware" then .hardware_verified else true end)
       and (if .status == "passed" then .summary.failed == 0 else .summary.failed > 0 end)
     else .error != null and .hardware_verified == false end);
common and (if $kind == "manifest" then manifest elif $kind == "status" then status
  elif $kind == "result" then result else false end)
