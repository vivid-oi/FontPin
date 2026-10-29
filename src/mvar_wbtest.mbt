///|
fn metric_test_mvar(tags : Array[String]) -> Bytes raise FontError {
  let out = Array::make(12 + tags.length() * 8, b'\x00')
  set_u16(out, 0, 1)
  set_u16(out, 6, 8)
  set_u16(out, 8, tags.length())
  set_u16(out, 10, out.length())
  for i, tag in tags {
    for j in 0..<4 {
      out[12 + i * 8 + j] = tag[j].to_int().to_byte()
    }
    set_u16(out, 12 + i * 8 + 6, i % 2)
  }
  for b in metric_test_store() {
    out.push(b)
  }
  Bytes::from_array(out[:])
}

///|
test "MVAR bakes global metrics and keeps originally synchronized line metrics synchronized" {
  let os2 = Array::make(96, b'\x00')
  let hhea = Array::make(36, b'\x00')
  set_u16(os2, 0, 4)
  set_i16(os2, 68, 800)
  set_i16(os2, 70, -200)
  set_i16(os2, 72, 100)
  set_i16(hhea, 4, 800)
  set_i16(hhea, 6, -200)
  set_i16(hhea, 8, 100)
  let original = Bytes::from_array(os2[:])
  let tables : Map[String, Bytes] = {
    "MVAR": metric_test_mvar(["hasc", "hdsc"]),
    "OS/2": original,
    "hhea": Bytes::from_array(hhea[:]),
  }
  apply_mvar(tables, [0.5])
  assert_eq(read_i16(tables["OS/2"], 68), 850)
  assert_eq(read_i16(tables["OS/2"], 70), -225)
  assert_eq(read_i16(tables["hhea"], 4), 850)
  assert_eq(read_i16(tables["hhea"], 6), -225)
  assert_eq(read_i16(original, 68), 800)
}

///|
test "MVAR preserves intentionally different hhea line metrics and rejects unsupported records atomically" {
  let os2 = Array::make(96, b'\x00')
  let hhea = Array::make(36, b'\x00')
  set_u16(os2, 0, 4)
  set_i16(os2, 68, 800)
  set_i16(hhea, 4, 900)
  let original = Bytes::from_array(os2[:])
  let tables : Map[String, Bytes] = {
    "MVAR": metric_test_mvar(["hasc"]),
    "OS/2": original,
    "hhea": Bytes::from_array(hhea[:]),
  }
  apply_mvar(tables, [1.0])
  assert_eq(read_i16(tables["hhea"], 4), 900)
  tables["OS/2"] = original
  tables["MVAR"] = metric_test_mvar(["hasc", "zzzz"])
  let mut caught = false
  try apply_mvar(tables, [1.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  assert_eq(tables["OS/2"], original)
}

///|
test "MVAR unsigned limits and malformed tables refuse rather than wrap" {
  let os2 = Array::make(96, b'\x00')
  set_u16(os2, 0, 4)
  set_u16(os2, 74, 65535)
  let original = Bytes::from_array(os2[:])
  let tables : Map[String, Bytes] = {
    "MVAR": metric_test_mvar(["hcla"]),
    "OS/2": original,
  }
  let mut caught = false
  try apply_mvar(tables, [1.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  assert_eq(tables["OS/2"], original)
  tables["MVAR"] = metric_test_mvar(["hdsc", "hasc"])
  caught = false
  try apply_mvar(tables, [0.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  tables["MVAR"] = b"\x00\x01\x00\x00\x00\x00\x00\x08\x00\x00\x00\x00"
  apply_mvar(tables, [0.0])
  assert_eq(tables["OS/2"], original)
}

///|
test "MVAR gasp changes preserve range ordering and never target the terminal range" {
  let gasp : Bytes = [0, 1, 0, 3, 0, 12, 0, 1, 0, 24, 0, 3, 0xff, 0xff, 0, 3]
  let tables : Map[String, Bytes] = {
    "MVAR": metric_test_mvar(["gsp0"]),
    "gasp": gasp,
  }
  apply_mvar(tables, [0.1])
  assert_eq(read_u16(tables["gasp"], 4), 22)
  assert_eq(read_u16(tables["gasp"], 8), 24)
  tables["gasp"] = gasp
  let mut caught = false
  try apply_mvar(tables, [0.5]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  assert_eq(tables["gasp"], gasp)
  tables["MVAR"] = metric_test_mvar(["gsp2"])
  caught = false
  try apply_mvar(tables, [0.0]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
}

///|
test "MVAR rejects every truncated declared store and old OS2 x-height fields" {
  let mvar = metric_test_mvar(["xhgt"])
  let os2 = Array::make(96, b'\x00')
  set_u16(os2, 0, 1)
  let original = Bytes::from_array(os2[:])
  for length in 0..<mvar.length() {
    let tables : Map[String, Bytes] = {
      "MVAR": mvar[0:length].to_owned(),
      "OS/2": original,
    }
    let mut caught = false
    try apply_mvar(tables, [0.5]) catch {
      _ => caught = true
    } noraise {
      _ => ()
    }
    assert_true(caught)
    assert_eq(tables["OS/2"], original)
  }
  let tables : Map[String, Bytes] = { "MVAR": mvar, "OS/2": original }
  let mut caught = false
  try apply_mvar(tables, [0.5]) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
}

///|
test "MVAR parsing and evaluation limits reject atomically and permit a later conversion" {
  let original = Bytes::from_array(Array::make(96, b'\x00')[:])
  let tables : Map[String, Bytes] = {
    "MVAR": metric_test_mvar(["hasc", "hdsc", "hlgp"]),
    "OS/2": original,
  }
  try apply_mvar(tables, [1.0], work_limit=1) catch {
    Limit(message) =>
      assert_eq(message, "variation region index budget exceeded")
    _ => fail("expected MVAR variation parser budget limit")
  } noraise {
    _ => fail("expected MVAR variation parser budget limit")
  }
  assert_eq(tables["OS/2"], original)
  try apply_mvar(tables, [1.0], work_limit=2) catch {
    Limit(message) =>
      assert_eq(message, "MVAR delta evaluation budget exceeded")
    _ => fail("expected MVAR evaluation budget limit")
  } noraise {
    _ => fail("expected MVAR evaluation budget limit")
  }
  assert_eq(tables["OS/2"], original)
  apply_mvar(tables, [1.0], work_limit=3)
  assert_eq(read_i16(tables["OS/2"], 68), 100)
  assert_eq(read_i16(tables["OS/2"], 70), -50)
  assert_eq(read_i16(tables["OS/2"], 72), 100)
}

///|
test "MVAR zero-record header refuses unexplained extension bytes" {
  let original = b"\x00\x00"
  let tables : Map[String, Bytes] = {
    "MVAR": b"\x00\x01\x00\x00\x00\x00\x00\x08\x00\x00\x00\x00\x01",
    "post": original,
  }
  try apply_mvar(tables, [0.0]) catch {
    Unsupported(message) =>
      assert_eq(message, "unexplained bytes after empty MVAR header")
    _ => fail("expected unsupported MVAR header extension")
  } noraise {
    _ => fail("expected unsupported MVAR header extension")
  }
  assert_eq(tables["post"], original)
}
