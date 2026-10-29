///|
fn hvar_rsb_test_table(
  advance : Int32,
  left : Int32,
  right : Int32,
) -> Bytes raise FontError {
  let store = byte_array(metric_test_store())
  set_u16(store, 22, 3)
  set_i16(store, 30, advance)
  set_i16(store, 32, left)
  push_i16(store, right)
  let out = Array::make(20, (0 : Byte))
  set_u16(out, 0, 1)
  set_u32(out, 4, 20U)
  for byte in store {
    out.push(byte)
  }
  for (field, row) in [(8, 0), (12, 1), (16, 2)] {
    set_u32(out, field, out.length().reinterpret_as_uint())
    for byte in [0, 1, 0, 1, row] {
      out.push(byte.to_byte())
    }
  }
  Bytes::from_array(out[:])
}

///|
test "HVAR right mappings freeze both bearings against varied outline widths" {
  let tables = api_fixture_tables()
  tables["HVAR"] = hvar_rsb_test_table(100, 10, 80)
  let source = build_sfnt(tables, 100000)
  let font = Font::parse(source)
  for
    (weight, advance, left, right) in [
      (400.0, 500, 0, 400),
      (550.0, 550, 5, 440),
      (700.0, 600, 10, 480),
    ] {
    let output = font.instantiate({ "wght": weight }).to_bytes()
    let result = parse_sfnt(output, 100000)
    let width = metric_outline_size(result, 0, false)
    assert_eq(read_u16(result["hmtx"], 0), advance)
    assert_eq(read_i16(result["hmtx"], 2), left)
    assert_eq(advance - left - width, right)
    assert_eq(read_i16(result["hhea"], 14), right)
    assert_false(result.contains("HVAR"))
    assert_eq(build_sfnt(result, 100000), output)
    assert_eq(font.instantiate({ "wght": weight }).to_bytes(), output)
  }
  assert_eq(parse_sfnt(source, 100000)["hmtx"], tables["hmtx"])
}

///|
test "HVAR right-only maps derive left bearings and combine fractions before rounding" {
  let tables = api_fixture_tables()
  let bytes = byte_array(hvar_rsb_test_table(100, 10, 80))
  set_u32(bytes, 12, 0U)
  tables["HVAR"] = Bytes::from_array(bytes[:])
  let output = parse_sfnt(
    Font::parse(build_sfnt(tables, 100000))
    .instantiate({ "wght": 700.0 })
    .to_bytes(),
    100000,
  )
  assert_eq(read_i16(output["hmtx"], 2), 10)
  tables["HVAR"] = hvar_rsb_test_table(0, 1, -11)
  let output = parse_sfnt(
    Font::parse(build_sfnt(tables, 100000))
    .instantiate({ "wght": 550.0 })
    .to_bytes(),
    100000,
  )
  assert_eq(read_i16(output["hmtx"], 2), 1)
}

///|
test "HVAR contradictory bearings fail atomically and valid positions recover" {
  let tables = api_fixture_tables()
  tables["HVAR"] = hvar_rsb_test_table(100, 10, 81)
  let font = Font::parse(build_sfnt(tables, 100000))
  let expected = font.instantiate({}).to_bytes()
  assert_true(
    try {
      ignore(font.instantiate({ "wght": 700.0 }))
      false
    } catch {
      Invalid(detail) => detail.contains("cannot both")
      _ => false
    },
  )
  assert_eq(font.instantiate({}).to_bytes(), expected)
  let bytes = byte_array(hvar_rsb_test_table(0, 0, 32767))
  set_u32(bytes, 12, 0U)
  tables["HVAR"] = Bytes::from_array(bytes[:])
  assert_true(
    try {
      ignore(
        Font::parse(build_sfnt(tables, 100000)).instantiate({ "wght": 700.0 }),
      )
      false
    } catch {
      Invalid(detail) => detail.contains("overflow")
      _ => false
    },
  )
}

///|
test "HVAR right mapping truncation, invalid offsets and extra evaluation work are checked" {
  let tables = api_fixture_tables()
  let valid = hvar_rsb_test_table(100, 10, 80)
  let shape = instantiate_glyphs(tables, [1.0], 1000)
  for length in 0..<valid.length() {
    tables["HVAR"] = valid[0:length].to_owned()
    assert_true(
      try {
        ignore(apply_hvar(tables, [1.0], shape.hmtx, outlines=Some(shape)))
        false
      } catch {
        _ => true
      },
    )
  }
  let invalid = byte_array(valid)
  set_u32(invalid, 16, 8U)
  tables["HVAR"] = Bytes::from_array(invalid[:])
  assert_true(
    try {
      ignore(apply_hvar(tables, [1.0], shape.hmtx, outlines=Some(shape)))
      false
    } catch {
      Invalid(_) => true
      _ => false
    },
  )
  tables["HVAR"] = valid
  assert_true(
    try {
      ignore(
        apply_hvar(
          tables,
          [1.0],
          shape.hmtx,
          outlines=Some(shape),
          work_limit=2,
        ),
      )
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  let result = apply_hvar(
    tables,
    [1.0],
    shape.hmtx,
    outlines=Some(shape),
    work_limit=3,
  )
  assert_eq(read_i16(result, 2), 10)
}
