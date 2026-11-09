length == 1 and (.[0] | type == "array" and length > 0 and
  all(to_entries[]; .key == .value.vector_index and (.value |
    (.reset_before | type == "boolean") and
    (.din | type == "string" and test("\\A0x[0-3][0-9a-f]{2}\\z")) and
    (.steps | type == "number" and . == floor and . >= 0 and . <= 65535) and
    all(.expected_dout, .mask; type == "string" and test("\\A0x[0-3][0-9a-f]{4}\\z")))))
