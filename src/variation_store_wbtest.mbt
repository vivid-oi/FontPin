///|
fn metric_test_store() -> Bytes raise FontError {
  let out : Array[Byte] = []
  push_u16(out, 1)
  push_u32(out, 12U)
  push_u16(out, 1)
  push_u32(out, 22U)
  push_u16(out, 1)
  push_u16(out, 1)
  push_i16(out, 0)
  push_i16(out, 16384)
  push_i16(out, 16384)
  push_u16(out, 2)
  push_u16(out, 1)
  push_u16(out, 1)
  push_u16(out, 0)
  push_i16(out, 100)
  push_i16(out, -50)
  Bytes::from_array(out[:])
}

///|
test "item variations interpolate independently, preserve signs and handle no variation sentinel" {
  let bytes = metric_test_store()
  let half = variation_store(bytes, 0, [0.5])
  assert_eq(variation_delta(half, 0, 0), 50.0)
  assert_eq(variation_delta(half, 0, 1), -25.0)
  assert_eq(variation_delta(half, 65535, 65535), 0.0)
  assert_eq(variation_delta(variation_store(bytes, 0, [0.0]), 0, 0), 0.0)
  assert_eq(variation_delta(variation_store(bytes, 0, [1.0]), 0, 0), 100.0)
  assert_eq(variation_delta(variation_store(bytes, 0, [-1.0]), 0, 0), 0.0)
  let mut caught = false
  try variation_delta(half, 1, 0) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  caught = false
  try variation_delta(half, 0, 2) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
}

///|
test "item variation stores reject every truncation and malformed counts" {
  let bytes = metric_test_store()
  for length in 0..<bytes.length() {
    let mut caught = false
    try variation_store(bytes[0:length].to_owned(), 0, [0.5]) catch {
      _ => caught = true
    } noraise {
      _ => ()
    }
    assert_true(caught)
  }
  let bad = byte_array(bytes)
  set_u16(bad, 24, 2)
  let mut caught = false
  try variation_store(Bytes::from_array(bad[:]), 0, [0.5]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  caught = false
  try variation_store(bytes, 0, [0.5, 0.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  // Error recovery is stateless: a malformed store does not poison a later parse.
  assert_eq(variation_delta(variation_store(bytes, 0, [0.5]), 0, 0), 50.0)
}

///|
test "delta index mappings decode packed indices and repeat last entry" {
  let format0 : Bytes = [0, 0x12, 0, 2, 0, 9, 0, 23]
  assert_eq(delta_index_map(format0, 0, 0), (1, 1))
  assert_eq(delta_index_map(format0, 0, 1), (2, 7))
  assert_eq(delta_index_map(format0, 0, 500), (2, 7))
  let format1 : Bytes = [1, 0x3f, 0, 0, 0, 1, 0xff, 0xff, 0xff, 0xff]
  assert_eq(delta_index_map(format1, 0, 0), (65535, 65535))
  let mut caught = false
  try delta_index_map(b"\x00\x00\x00\x00", 0, 0) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  caught = false
  try delta_index_map(b"\x00\xc0\x00\x01\x00", 0, 0) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
}

///|
test "long word variation deltas retain full signed 32-bit values" {
  let bytes = byte_array(metric_test_store())
  set_u16(bytes, 24, 0x8001)
  // Rebuild the last two 16-bit rows as 32-bit rows.
  let out : Array[Byte] = []
  for i in 0..<30 {
    out.push(bytes[i])
  }
  push_u32(out, 2147483647U)
  push_u32(out, 2147483648U)
  let store = variation_store(Bytes::from_array(out[:]), 0, [1.0])
  assert_eq(variation_delta(store, 0, 0), 2147483647.0)
  assert_eq(variation_delta(store, 0, 1), -2147483648.0)
}

///|
test "mixed short and byte delta columns are signed and weighted by independent regions" {
  let out : Array[Byte] = []
  push_u16(out, 1)
  push_u32(out, 12U)
  push_u16(out, 1)
  push_u32(out, 28U)
  push_u16(out, 1)
  push_u16(out, 2)
  for v in [0, 16384, 16384, -16384, -16384, 0] {
    push_i16(out, v)
  }
  push_u16(out, 1)
  push_u16(out, 1)
  push_u16(out, 2)
  push_u16(out, 0)
  push_u16(out, 1)
  push_i16(out, 1000)
  out.push(b'\x80')
  let bytes = Bytes::from_array(out[:])
  assert_eq(variation_delta(variation_store(bytes, 0, [0.5]), 0, 0), 500.0)
  assert_eq(variation_delta(variation_store(bytes, 0, [-0.5]), 0, 0), -64.0)
  assert_eq(variation_delta(variation_store(bytes, 0, [0.0]), 0, 0), 0.0)
}

///|
test "item variation parsing charges scalar and index work before allocation" {
  let bytes = metric_test_store()
  try variation_store(bytes, 0, [1.0], work_limit=1) catch {
    Limit(message) =>
      assert_eq(message, "variation region index budget exceeded")
    _ => fail("expected an item variation work limit")
  } noraise {
    _ => fail("expected an item variation work limit")
  }
  assert_eq(
    variation_delta(variation_store(bytes, 0, [1.0], work_limit=2), 0, 0),
    100.0,
  )
}
