# Filesystem containment is checked by the dispatcher.
include "output-match" {search:"./"};

def fields($names): type == "object" and keys == ($names | sort);
def member($values): . as $v | $values | index($v) != null;
def uuid: type == "string" and test("\\A[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\\z");
def utc: type == "string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z");
def maybe_time: . == null or utc;
def natural: type == "number" and . >= 0 and floor == .;
def relative: type == "string" and test("\\A[A-Za-z0-9_-][A-Za-z0-9_./-]*\\z")
  and (split("/") | all(. != ".." and . != "." and . != ""));
def final_status: member(["passed","mismatch","build_error","board_error","invalid_input","busy","internal_error"]);
def stage: member(["dispatch","validating","locking","building","programming","testing","finalizing"]);
def common: type == "object" and (.run_id | uuid);
def mode: .mode | member(["hardware","mock"]);
def manifest:
  (if .schema_version == 1 then
      fields(["kind","run_id","schema_version","sources","test_set","top"])
   elif .schema_version == 2 then
      fields(["kind","language","run_id","schema_version","sources","test_set","top"])
      and (.language | member(["verilog","systemverilog"]))
   else false end)
  and .top == "student_top"
  and ($ARGS.named.run_id == null or .run_id == $ARGS.named.run_id)
  and (.kind | member(["combinational","sequential"]))
  and ((.language == "systemverilog") as $systemverilog
       | .sources | type == "array" and length > 0 and length == (unique | length)
       and all(.[]; relative and (endswith(".v") or ($systemverilog and endswith(".sv")))))
  and (.test_set | type == "string" and test("\\A[A-Za-z0-9_-]+\\z"));
def status:
  fields(["schema_version","run_id","mode","state","stage","started_at","updated_at",
          "finished_at","result_status"])
  and mode and (.stage | stage) and (.updated_at | utc) and (.started_at | maybe_time)
  and (.started_at == null or .started_at <= .updated_at)
  and (if .state == "starting" then .stage == "dispatch" and .started_at == null
       and .finished_at == null and .result_status == null
    elif .state == "running" then (.started_at | utc) and .finished_at == null and .result_status == null
    elif .state == "finished" then .stage == "finalizing" and (.finished_at | utc)
       and .finished_at <= .updated_at and (.started_at == null or .started_at <= .finished_at)
       and (.result_status | final_status) else false end);
def summary:
  fields(["planned","executed","passed","failed"])
  and all(.[]; natural) and .executed <= .planned and .passed + .failed == .executed;
def observation:
  fields(["vector_index","din","steps","dout","expected_dout","mask","match"])
  and (.vector_index | natural) and (.steps | natural) and (.match | type == "boolean")
  and (.din | type == "string" and test("\\A0x[0-3][0-9a-f]{2}\\z"))
  and all(.dout,.expected_dout,.mask; type == "string" and test("\\A0x[0-3][0-9a-f]{4}\\z"))
  and (. as $obs | .dout | hex | matches(($obs.expected_dout | hex); ($obs.mask | hex))) == .match;
def result:
  fields(["schema_version","run_id","mode","status","hardware_verified","started_at",
          "finished_at","summary","observations","error","logs"])
  and mode and (.status | final_status) and (.hardware_verified | type == "boolean")
  and (if .mode == "mock" then .hardware_verified == false else true end)
  and (.started_at | maybe_time) and (.finished_at | utc) and (.summary | summary)
  and (.started_at == null or .started_at <= .finished_at)
  and (.observations | type == "array" and all(.[]; observation))
  and ([.observations[].vector_index] | unique | length) == .summary.executed
  and (.observations | length) == .summary.executed
  and ([.observations[] | select(.match)] | length) == .summary.passed
  and (.logs | type == "array" and all(.[]; relative))
  and (.error == null or (.error | fields(["stage","code","message"])
       and (.stage | stage) and (.code | type == "string") and (.message | type == "string")))
  and (if .status == "passed" or .status == "mismatch" then
       .error == null and (.started_at | utc) and .summary.executed == .summary.planned
       and (if .mode == "hardware" then .hardware_verified else true end)
       and (if .status == "passed" then .summary.failed == 0 else .summary.failed > 0 end)
     else .error != null and .hardware_verified == false end);
common and (if $kind == "manifest" then manifest
  elif .schema_version != 1 then false elif $kind == "status" then status
  elif $kind == "result" then result else false end)
