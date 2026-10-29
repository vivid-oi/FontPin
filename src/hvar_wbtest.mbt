///|
test "HVAR overrides phantom advance using original metrics without double counting" {
  let hvar = Array::make(20, b'\x00')
  set_u16(hvar, 0, 1)
  set_u32(hvar, 4, 20U)
  let store = metric_test_store()
  for b in store {
    hvar.push(b)
  }
  let header = Array::make(36, b'\x00')
  set_u16(header, 34, 2)
  let original : Bytes = [1, 144, 0, 10, 2, 88, 0, 20]
  let phantom : Bytes = [1, 244, 0, 15, 2, 138, 0, 25]
  let tables : Map[String, Bytes] = {
    "HVAR": Bytes::from_array(hvar[:]),
    "hhea": Bytes::from_array(header[:]),
    "hmtx": original,
  }
  let result = apply_hvar(tables, [0.5], phantom)
  assert_eq(read_u16(result, 0), 450)
  assert_eq(read_u16(result, 4), 575)
  assert_eq(read_i16(result, 2), 15)
  assert_eq(read_i16(result, 6), 25)
  assert_eq(original, tables["hmtx"])
  assert_eq(apply_hvar(Map([]), [0.5], phantom), phantom)
}

///|
test "HVAR mapped shared advances and absent long metrics are checked" {
  let hvar = Array::make(20, b'\x00')
  set_u16(hvar, 0, 1)
  set_u32(hvar, 4, 20U)
  let store = metric_test_store()
  for b in store {
    hvar.push(b)
  }
  set_u32(hvar, 8, hvar.length().reinterpret_as_uint())
  for b in [b'\x00', b'\x00', b'\x00', b'\x01', b'\x00'] {
    hvar.push(b)
  }
  let header = Array::make(36, b'\x00')
  set_u16(header, 34, 1)
  let original : Bytes = [1, 144, 0, 10, 0, 20]
  let phantom : Bytes = [1, 144, 0, 10, 1, 144, 0, 20]
  let tables : Map[String, Bytes] = {
    "HVAR": Bytes::from_array(hvar[:]),
    "hhea": Bytes::from_array(header[:]),
    "hmtx": original,
  }
  let result = apply_hvar(tables, [1.0], phantom)
  assert_eq(read_u16(result, 0), 500)
  assert_eq(read_u16(result, 4), 500)
  set_u16(header, 34, 0)
  tables["hhea"] = Bytes::from_array(header[:])
  let mut caught = false
  try apply_hvar(tables, [0.5], phantom) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
}

///|
test "HVAR explicit bearing maps use original bearings while advance overflow is refused" {
  let hvar = Array::make(20, b'\x00')
  set_u16(hvar, 0, 1)
  set_u32(hvar, 4, 20U)
  for b in metric_test_store() {
    hvar.push(b)
  }
  set_u32(hvar, 12, hvar.length().reinterpret_as_uint())
  for b in [b'\x00', b'\x00', b'\x00', b'\x01', b'\x01'] {
    hvar.push(b)
  }
  let header = Array::make(36, b'\x00')
  set_u16(header, 34, 2)
  let original : Bytes = [1, 144, 0, 10, 2, 88, 0, 20]
  let phantom : Bytes = [1, 244, 0, 15, 2, 138, 0, 25]
  let tables : Map[String, Bytes] = {
    "HVAR": Bytes::from_array(hvar[:]),
    "hhea": Bytes::from_array(header[:]),
    "hmtx": original,
  }
  let result = apply_hvar(tables, [0.5], phantom)
  assert_eq(read_i16(result, 2), -15)
  assert_eq(read_i16(result, 6), -5)
  tables["hmtx"] = b"\xff\xff\x00\x0a\x02\x58\x00\x14"
  let mut caught = false
  try apply_hvar(tables, [1.0], phantom) catch {
    _ => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  tables["hmtx"] = original
  assert_eq(apply_hvar(tables, [0.5], phantom), result)
}

///|
test "HVAR evaluation budget covers repeated mapped rows and remains recoverable" {
  let hvar = Array::make(20, b'\x00')
  set_u16(hvar, 0, 1)
  set_u32(hvar, 4, 20U)
  for b in metric_test_store() {
    hvar.push(b)
  }
  set_u32(hvar, 8, hvar.length().reinterpret_as_uint())
  for b in [b'\x00', b'\x00', b'\x00', b'\x01', b'\x00'] {
    hvar.push(b)
  }
  let header = Array::make(36, b'\x00')
  set_u16(header, 34, 1)
  let original : Bytes = [1, 144, 0, 10, 0, 20, 0, 30, 0, 40]
  let phantom : Bytes = [
    1, 144, 0, 10, 1, 144, 0, 20, 1, 144, 0, 30, 1, 144, 0, 40,
  ]
  let tables : Map[String, Bytes] = {
    "HVAR": Bytes::from_array(hvar[:]),
    "hhea": Bytes::from_array(header[:]),
    "hmtx": original,
  }
  try apply_hvar(tables, [1.0], phantom, work_limit=3) catch {
    Limit(message) =>
      assert_eq(message, "HVAR delta evaluation budget exceeded")
    _ => fail("expected an HVAR budget limit")
  } noraise {
    _ => fail("expected an HVAR budget limit")
  }
  assert_eq(tables["hmtx"], original)
  let result = apply_hvar(tables, [1.0], phantom, work_limit=4)
  for gid in 0..<4 {
    assert_eq(read_u16(result, gid * 4), 500)
  }
}

///|
test "HVAR malformed mapping and unexplained original metric bytes are refused" {
  let hvar = Array::make(20, b'\x00')
  set_u16(hvar, 0, 1)
  set_u32(hvar, 4, 20U)
  for b in metric_test_store() {
    hvar.push(b)
  }
  let header = Array::make(36, b'\x00')
  set_u16(header, 34, 2)
  let original : Bytes = [1, 144, 0, 10, 2, 88, 0, 20]
  let tables : Map[String, Bytes] = {
    "HVAR": Bytes::from_array(hvar[:]),
    "hhea": Bytes::from_array(header[:]),
    "hmtx": original,
  }
  for length in 0..<hvar.length() {
    tables["HVAR"] = Bytes::from_array(hvar[0:length])
    try apply_hvar(tables, [1.0], original) catch {
      _ => ()
    } noraise {
      _ => fail("expected truncated HVAR rejection")
    }
  }
  set_u32(hvar, 16, 20U)
  tables["HVAR"] = Bytes::from_array(hvar[:])
  try apply_hvar(tables, [1.0], original) catch {
    Invalid(_) => ()
    _ => fail("expected invalid right-side-bearing map/context")
  } noraise {
    _ => fail("expected invalid right-side-bearing map/context")
  }
  set_u32(hvar, 16, 0U)
  tables["HVAR"] = Bytes::from_array(hvar[:])
  tables["hmtx"] = b"\x01\x90\x00\x0a\x02\x58\x00\x14\x00"
  try apply_hvar(tables, [1.0], original) catch {
    Invalid(_) => ()
    _ => fail("expected extra original metric bytes rejection")
  } noraise {
    _ => fail("expected extra original metric bytes rejection")
  }
  tables["hmtx"] = original
  assert_eq(read_u16(apply_hvar(tables, [1.0], original), 0), 500)
}
