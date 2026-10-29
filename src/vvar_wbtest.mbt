///|
fn vvar_test_table(
  advance : Int32,
  top : Int32,
  bottom : Int32,
) -> Bytes raise FontError {
  // Three delta rows sharing the same positive-axis region.
  let store = byte_array(metric_test_store())
  set_u16(store, 22, 3)
  set_i16(store, 30, advance)
  set_i16(store, 32, top)
  push_i16(store, bottom)
  let out = Array::make(24, (0 : Byte))
  set_u16(out, 0, 1)
  set_u32(out, 4, 24U)
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
test "VVAR explicit maps use original baseline and coherent top/bottom metrics" {
  let tables = vertical_test_tables()
  tables["VVAR"] = vvar_test_table(100, -20, 120)
  let source = build_sfnt(tables, 100000)
  let font = Font::parse(source)
  for
    (weight, height, bearing) in [
      (400.0, 1000, 100),
      (550.0, 1050, 90),
      (700.0, 1100, 80),
    ] {
    let output = font.instantiate({ "wght": weight }).to_bytes()
    let after = parse_sfnt(output, 100000)
    assert_false(after.contains("VVAR"))
    assert_eq(read_u16(after["vmtx"], 0), height)
    assert_eq(read_i16(after["vmtx"], 2), bearing)
    assert_eq(read_u16(after["vhea"], 10), height)
    assert_eq(font.instantiate({ "wght": weight }).to_bytes(), output)
    assert_eq(build_sfnt(after, 100000), output)
  }
  assert_eq(parse_sfnt(source, 100000)["vmtx"], tables["vmtx"])
}

///|
test "VVAR absent maps use implicit advance indices and gvar bearings" {
  let tables = vertical_test_tables()
  let bytes = byte_array(vvar_test_table(100, 0, 0))
  set_u32(bytes, 8, 0U)
  set_u32(bytes, 12, 0U)
  set_u32(bytes, 16, 0U)
  tables["VVAR"] = Bytes::from_array(bytes[:])
  let glyphs = instantiate_glyphs(tables, [0.5], 1000)
  guard apply_vvar(tables, [0.5], glyphs, 1000) is Some(result) else {
    fail("missing VVAR result")
  }
  assert_eq(read_u16(result, 0), 1050)
  assert_eq(read_i16(result, 2), 100)
  // Bottom-only mapping derives a top bearing; it is not silently ignored.
  tables["VVAR"] = vvar_test_table(100, -20, 120)
  let bottom_only = byte_array(tables["VVAR"])
  set_u32(bottom_only, 12, 0U)
  tables["VVAR"] = Bytes::from_array(bottom_only[:])
  guard apply_vvar(tables, [1.0], glyphs, 1000) is Some(result) else {
    fail("missing result")
  }
  assert_eq(read_i16(result, 2), 80)
}

///|
test "VVAR complementary half-unit bearings are combined before rounding" {
  let tables = vertical_test_tables()
  tables["VVAR"] = vvar_test_table(0, 1, -1)
  let font = Font::parse(build_sfnt(tables, 100000))
  let output = parse_sfnt(
    font.instantiate({ "wght": 550.0 }).to_bytes(),
    100000,
  )
  assert_eq(read_u16(output["vmtx"], 0), 1000)
  assert_eq(read_i16(output["vmtx"], 2), 101)
}

///|
test "VVAR conflicting metrics reject atomically and preserve source for recovery" {
  let tables = vertical_test_tables()
  tables["VVAR"] = vvar_test_table(100, -20, 121)
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
  for
    (advance, top, bottom) in [
      (32767, 0, 32767),
      (-2000, 0, -2000),
      (0, 32767, -32767),
    ] {
    let bad = vertical_test_tables()
    bad["VVAR"] = vvar_test_table(advance, top, bottom)
    if advance == 32767 {
      bad["vmtx"] = b"\xff\xff\x00\x64"
    }
    assert_true(
      try {
        ignore(
          Font::parse(build_sfnt(bad, 100000)).instantiate({ "wght": 700.0 }),
        )
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
}

///|
test "VVAR validates map formats, versions, truncation, missing metrics and budgets" {
  let tables = vertical_test_tables()
  let valid = vvar_test_table(100, -20, 120)
  for length in 0..<valid.length() {
    let bad = tables.copy()
    bad["VVAR"] = valid[0:length].to_owned()
    assert_true(
      try {
        ignore(Font::parse(build_sfnt(bad, 100000)).instantiate({}))
        false
      } catch {
        Invalid(_) | Limit(_) => true
        _ => false
      },
    )
  }
  for (offset, value) in [(4, 8U), (8, 4U), (20, 24U), (0, 0x00020000U)] {
    let bytes = byte_array(valid)
    set_u32(bytes, offset, value)
    let bad = tables.copy()
    bad["VVAR"] = Bytes::from_array(bytes[:])
    assert_true(
      try {
        ignore(Font::parse(build_sfnt(bad, 100000)).instantiate({}))
        false
      } catch {
        _ => true
      },
    )
  }
  tables["VVAR"] = valid
  let nonstandard_map = byte_array(valid)
  nonstandard_map[read_u32(valid, 8)] = 1
  tables["VVAR"] = Bytes::from_array(nonstandard_map[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).instantiate({}))
      false
    } catch {
      Unsupported(detail) => detail.contains("format 0")
      _ => false
    },
  )
  tables["VVAR"] = valid
  let glyphs = instantiate_glyphs(tables, [1.0], 1000)
  assert_true(
    try {
      ignore(apply_vvar(tables, [1.0], glyphs, 1))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  tables.remove("vmtx")
  tables.remove("vhea")
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).instantiate({}))
      false
    } catch {
      Invalid(detail) => detail.contains("VVAR requires")
      _ => false
    },
  )
}
