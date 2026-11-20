def hex:
  ltrimstr("0x") | reduce explode[] as $char
    (0; . * 16 + (if $char <= 57 then $char - 48 else $char - 87 end));

def matches($expected; $mask):
  . as $actual |
  all(range(0;18);
    pow(2; .) as $bit |
    (($mask / $bit | floor % 2) == 0) or
    (($actual / $bit | floor % 2) == ($expected / $bit | floor % 2)));
