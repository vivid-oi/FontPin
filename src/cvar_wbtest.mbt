///|
fn metric_test_cvar(private_points : Bool) -> Bytes raise FontError {
  let out : Array[Byte] = []
  push_u16(out, 1)
  push_u16(out, 0)
  push_u16(out, 1)
  push_u16(out, 14)
  push_u16(out, if private_points { 7 } else { 4 })
  push_u16(out, if private_points { 0xa000 } else { 0x8000 })
  push_i16(out, 16384)
  if private_points {
    // CVT entries 0 and 2, not entry 1. No IUP is applied to entry 1.
    out.push(b'\x02')
    out.push(b'\x01')
    out.push(b'\x00')
    out.push(b'\x02')
    out.push(b'\x01')
    out.push(b'\x14')
    out.push(b'\xf6')
  } else {
    out.push(b'\x02')
    out.push(b'\x14')
    out.push(b'\x00')
    out.push(b'\xf6')
  }
  Bytes::from_array(out[:])
}

///|
test "cvar bakes all CVTs and preserves original table bytes" {
  let cvt : Bytes = [0, 100, 0, 200, 0xff, 0x9c]
  let tables : Map[String, Bytes] = {
    "cvar": metric_test_cvar(false),
    "cvt ": cvt,
  }
  apply_cvar(tables, [0.5])
  assert_eq(read_i16(tables["cvt "], 0), 110)
  assert_eq(read_i16(tables["cvt "], 2), 200)
  assert_eq(read_i16(tables["cvt "], 4), -105)
  assert_eq(read_i16(cvt, 0), 100)
}

///|
test "cvar sparse deltas do not infer deltas for unlisted control values" {
  let cvt : Bytes = [0, 100, 0, 200, 0xff, 0x9c]
  let tables : Map[String, Bytes] = {
    "cvar": metric_test_cvar(true),
    "cvt ": cvt,
  }
  apply_cvar(tables, [1.0])
  assert_eq(read_i16(tables["cvt "], 0), 120)
  assert_eq(read_i16(tables["cvt "], 2), 200)
  assert_eq(read_i16(tables["cvt "], 4), -110)
}

///|
test "cvar rejects truncated tuples and missing embedded peaks without mutating CVT" {
  let cvar = metric_test_cvar(true)
  let cvt : Bytes = [0, 100, 0, 200, 0xff, 0x9c]
  for length in 0..<cvar.length() {
    let tables : Map[String, Bytes] = {
      "cvar": cvar[0:length].to_owned(),
      "cvt ": cvt,
    }
    let mut caught = false
    try apply_cvar(tables, [0.5]) catch {
      _ => caught = true
    } noraise {
      _ => ()
    }
    assert_true(caught)
    assert_eq(tables["cvt "], cvt)
  }
  let malformed = byte_array(cvar)
  set_u16(malformed, 10, 0x2000)
  let tables : Map[String, Bytes] = {
    "cvar": Bytes::from_array(malformed[:]),
    "cvt ": cvt,
  }
  let mut caught = false
  try apply_cvar(tables, [1.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  assert_eq(tables["cvt "], cvt)
}

///|
test "cvar control value overflow refuses output and later valid conversion recovers" {
  let cvt : Bytes = [0x7f, 0xff, 0, 200, 0xff, 0x9c]
  let tables : Map[String, Bytes] = {
    "cvar": metric_test_cvar(false),
    "cvt ": cvt,
  }
  let mut caught = false
  try apply_cvar(tables, [1.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  assert_eq(tables["cvt "], cvt)
  apply_cvar(tables, [0.0])
  assert_eq(tables["cvt "], cvt)
}

///|
test "cvar duplicate indices accumulate and shared point numbers apply to each tuple" {
  let duplicate = byte_array(metric_test_cvar(true))
  duplicate[17] = b'\x00'
  duplicate[19] = b'\x0a'
  duplicate[20] = b'\x14'
  let single : Map[String, Bytes] = {
    "cvar": Bytes::from_array(duplicate[:]),
    "cvt ": b"\x00\x64",
  }
  apply_cvar(single, [0.5])
  assert_eq(read_i16(single["cvt "], 0), 115)
  let out : Array[Byte] = []
  push_u16(out, 1)
  push_u16(out, 0)
  push_u16(out, 0x8002)
  push_u16(out, 20)
  for _ in 0..<2 {
    push_u16(out, 3)
    push_u16(out, 0x8000)
    push_i16(out, 16384)
  }
  for
    b in [
      b'\x02', b'\x01', b'\x00', b'\x02', b'\x01', b'\x14', b'\xf6', b'\x01', b'\x0a',
      b'\xfb',
    ] {
    out.push(b)
  }
  let shared : Map[String, Bytes] = {
    "cvar": Bytes::from_array(out[:]),
    "cvt ": b"\x00\x64\x00\xc8\xff\x9c",
  }
  apply_cvar(shared, [0.5])
  assert_eq(read_i16(shared["cvt "], 0), 115)
  assert_eq(read_i16(shared["cvt "], 2), 200)
  assert_eq(read_i16(shared["cvt "], 4), -107)
}

///|
test "cvar budgets include initialization and tuple work and recover after exhaustion" {
  let source : Map[String, Bytes] = {
    "cvar": metric_test_cvar(false),
    "cvt ": b"\x00\x64\x00\xc8\xff\x9c",
  }
  for limit in [0, 1, 9, 12] {
    let request = source.copy()
    let rejected = try {
      apply_cvar(request, [0.5], work_limit=limit)
      false
    } catch {
      Limit(_) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(request["cvt "], source["cvt "])
  }
  let first = source.copy()
  let second = source.copy()
  apply_cvar(first, [0.5], work_limit=13)
  apply_cvar(second, [0.5], work_limit=13)
  assert_eq(first["cvt "], second["cvt "])
  assert_eq(read_i16(first["cvt "], 0), 110)
}

///|
test "cvar header gaps reject unexplained data and accept small zero alignment" {
  let data = metric_test_cvar(false)
  let cvt = b"\x00\x64\x00\xc8\xff\x9c"
  for
    padding in [
      b"\x00", b"\x00\x00", b"\x00\x00\x00", b"\x01", b"\x00\x00\x00\x00",
    ] {
    let aligned = byte_array(
      data[0:14].to_owned() + padding + data[14:].to_owned(),
    )
    set_u16(aligned, 6, 14 + padding.length())
    let tables : Map[String, Bytes] = {
      "cvar": Bytes::from_array(aligned[:]),
      "cvt ": cvt,
    }
    let success = try {
      apply_cvar(tables, [0.5])
      true
    } catch {
      Invalid(_) => false
      _ => fail("expected only a format diagnostic")
    }
    assert_eq(success, padding.length() <= 3 && padding[0] == 0)
    if success {
      assert_eq(read_i16(tables["cvt "], 0), 110)
    } else {
      assert_eq(tables["cvt "], cvt)
    }
  }
}

///|
test "cvar accepts empty CVT no-op tuples but zero tuple count is invalid by spec" {
  let empty : Map[String, Bytes] = {
    "cvar": b"\x00\x01\x00\x00\x00\x01\x00\x0e\x00\x00\x80\x00\x40\x00",
    "cvt ": b"",
  }
  apply_cvar(empty, [1.0])
  assert_eq(empty["cvt "], b"")
  let no_tuple : Map[String, Bytes] = {
    "cvar": b"\x00\x01\x00\x00\x00\x00\x00\x08",
    "cvt ": b"",
  }
  let rejected = try {
    apply_cvar(no_tuple, [1.0])
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "cvar rejects reserved flags, invalid regions and trailing data even at defaults" {
  let data = metric_test_cvar(false)
  let invalid : Array[Bytes] = []
  for flag in [0x1001, 0x2001, 0x4001] {
    let mutated = byte_array(data)
    set_u16(mutated, 4, flag)
    invalid.push(Bytes::from_array(mutated[:]))
  }
  let index = byte_array(data)
  set_u16(index, 10, 0x9000)
  invalid.push(Bytes::from_array(index[:]))
  invalid.push(data + b"\x00")
  let region = byte_array(
    data[0:14].to_owned() + b"\x00\x00\x20\x00" + data[14:].to_owned(),
  )
  set_u16(region, 6, 18)
  set_u16(region, 10, 0xc000)
  invalid.push(Bytes::from_array(region[:]))
  for cvar in invalid {
    let tables : Map[String, Bytes] = {
      "cvar": cvar,
      "cvt ": b"\x00\x64\x00\xc8\xff\x9c",
    }
    let original = tables["cvt "]
    let rejected = try {
      apply_cvar(tables, [0.0])
      false
    } catch {
      Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(tables["cvt "], original)
  }
}

///|
test "cvar cumulative repeated indices cannot wrap through Int32 and silently succeed" {
  // Eight legal private-point tuples each repeat CVT[0] 16384 times. Their
  // combined -2^32 delta would become zero if narrowed before range checking.
  let block : Array[Byte] = [b'\xc0', b'\x00']
  for _ in 0..<128 {
    block.push(b'\x7f')
    for _ in 0..<128 {
      block.push(0)
    }
  }
  for _ in 0..<256 {
    block.push(b'\x7f')
    for _ in 0..<64 {
      push_i16(block, -32768)
    }
  }
  let data : Array[Byte] = []
  push_u16(data, 1)
  push_u16(data, 0)
  push_u16(data, 8)
  push_u16(data, 56)
  for _ in 0..<8 {
    push_u16(data, block.length())
    push_u16(data, 0xa000)
    push_i16(data, 16384)
  }
  for _ in 0..<8 {
    for b in block {
      data.push(b)
    }
  }
  let tables : Map[String, Bytes] = {
    "cvar": Bytes::from_array(data[:]),
    "cvt ": b"\x00\x00",
  }
  let rejected = try {
    apply_cvar(tables, [1.0])
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(tables["cvt "], b"\x00\x00")
  apply_cvar(tables, [0.0])
  assert_eq(tables["cvt "], b"\x00\x00")
}
