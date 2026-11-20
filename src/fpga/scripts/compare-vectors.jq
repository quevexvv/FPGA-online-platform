include "output-match" {search:"./"};

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
