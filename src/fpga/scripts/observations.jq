($replies | split("\n")) as $parts |
($parts[:-1]) as $lines |
reduce $vectors[0][] as $vector (
  {offset:0, valid:true, observations:[]};
  if .valid then
    (if $vector.reset_before then 4 else 3 end) as $count |
    $lines[.offset:(.offset + $count)] as $part |
    if ($part | length == $count and all(.[:-1][]; . == "K") and
                (.[-1] | test("\\AD 0x[0-3][0-9a-f]{4}\\z"))) then
      .offset += $count |
      .observations += [($vector | {vector_index,din,steps}) + {dout:($part[-1] | ltrimstr("D "))}]
    else
      .valid = false
    end
  else
    .
  end
) |
{complete:(.valid and .offset == ($lines | length) and $parts[-1] == ""), observations}
