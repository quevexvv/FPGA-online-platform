def hex:
  ltrimstr("0x") | reduce explode[] as $char
    (0; . * 16 + (if $char <= 57 then $char - 48 else $char - 87 end));

def dout:
  . as $value | "0x" + ([65536,4096,256,16,1] |
    map(($value / . | floor % 16) as $digit | "0123456789abcdef"[$digit:($digit + 1)]) | join(""));

reduce $vectors[0][] as $vector (
  {value:0, observations:[]};
  ($vector.din | hex) as $din |
  if $model == "counter-v1" then
    .value = (((if $vector.reset_before then 0 else .value end) + $din * $vector.steps) % 262144)
  else
    .value = $din
  end |
  .observations += [($vector | {vector_index,din,steps}) + {dout:(.value | dout)}]
) | {observations}
