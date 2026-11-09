def hex:
  ltrimstr("0x") | reduce explode[] as $char
    (0; . * 16 + (if $char <= 57 then $char - 48 else $char - 87 end));

def matches($expected; $mask):
  . as $actual |
  all(range(0;18);
    pow(2; .) as $bit |
    (($mask / $bit | floor % 2) == 0) or
    (($actual / $bit | floor % 2) == ($expected / $bit | floor % 2)));

$report[0].observations | map(
  . as $observed |
  ($vectors[0][$observed.vector_index] | {expected_dout,mask}) as $reference |
  . + $reference +
    {match:(.dout | hex | matches(($reference.expected_dout | hex); ($reference.mask | hex)))}
) |
length as $executed |
(map(select(.match)) | length) as $passed |
{summary:{planned:($vectors[0] | length),executed:$executed,passed:$passed,failed:($executed - $passed)},
 observations:.}
