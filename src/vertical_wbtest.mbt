///|
fn vertical_test_tables() -> Map[String, Bytes] raise FontError {
  let tables = api_fixture_tables()
  let header = Array::make(36, (0 : Byte))
  set_u32(header, 0, 0x00011000U)
  set_u16(header, 34, 1)
  tables["vhea"] = Bytes::from_array(header[:])
  tables["vmtx"] = b"\x03\xe8\x00\x64"
  tables
}

///|
test "vertical phantom deltas preserve fractional origin until final bearing" {
  let source = vertical_test_tables()
  // Triangle: 3 points + 4 phantoms; one tuple varies top by +1, bottom by -2.
  let gvar = byte_array(source["gvar"])
  // Existing x deltas are retained. Replace all-zero y run by sparse full run.
  gvar[gvar.length() - 1] = 6
  for value in [0, 0, 0, 0, 0, 1, 254] {
    gvar.push(value.to_byte())
  }
  set_u32(gvar, 24, 26U)
  set_u16(gvar, 32, 16)
  source["gvar"] = Bytes::from_array(gvar[:])
  for
    (coord, height, bearing) in [
      (0.0, 1000, 100),
      (0.5, 1002, 101),
      (1.0, 1003, 101),
    ] {
    let result = instantiate_glyphs(source, [coord], 1000)
    guard result.vmtx is Some(metrics) else { fail("missing vertical metrics") }
    assert_eq(read_u16(metrics, 0), height)
    assert_eq(read_i16(metrics, 2), bearing)
    let output = parse_sfnt(
      Font::parse(build_sfnt(source, 100000))
      .instantiate({ "wght": 400.0 + coord * 300.0 })
      .to_bytes(),
      100000,
    )
    assert_eq(output["vmtx"], metrics)
    assert_eq(read_u16(output["vhea"], 10), height)
    assert_eq(read_i16(output["vhea"], 12), bearing)
    assert_eq(read_i16(output["vhea"], 14), height - bearing - 100)
    assert_eq(read_i16(output["vhea"], 16), bearing + 100)
    assert_eq(
      output["vhea"],
      parse_sfnt(
        Font::parse(build_sfnt(source, 100000))
        .instantiate({ "wght": 400.0 + coord * 300.0 })
        .to_bytes(),
        100000,
      )["vhea"],
    )
  }
}

///|
test "vertical tables reject missing pairs, truncated metrics and invalid headers" {
  let source = vertical_test_tables()
  let missing_header = source.copy()
  missing_header.remove("vhea")
  let missing_metrics = source.copy()
  missing_metrics.remove("vmtx")
  let invalid_count = source.copy()
  let header = byte_array(source["vhea"])
  set_u16(header, 34, 0)
  invalid_count["vhea"] = Bytes::from_array(header[:])
  let reserved = source.copy()
  set_u16(header, 34, 1)
  set_u16(header, 24, 1)
  reserved["vhea"] = Bytes::from_array(header[:])
  let extra = source.copy()
  extra["vmtx"] = source["vmtx"] + b"\x00"
  for bad in [missing_header, missing_metrics, invalid_count, reserved, extra] {
    assert_true(
      try {
        ignore(instantiate_glyphs(bad, [0.0], 1000))
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
  for length in 0..<4 {
    let bad = source.copy()
    bad["vmtx"] = source["vmtx"][0:length].to_owned()
    assert_true(
      try {
        ignore(instantiate_glyphs(bad, [0.0], 1000))
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
  assert_eq(instantiate_glyphs(source, [0.0], 1000).vmtx, Some(source["vmtx"]))
}

///|
test "vertical compressed metrics expand without changing advance or signed bearings" {
  let tables = vertical_test_tables()
  tables["vmtx"] = b"\x03\xe8\x00\x64\xff\xff\x00\x32"
  guard vertical_metrics(tables, 3) is Some((data, count)) else {
    fail("missing metrics")
  }
  assert_eq(glyph_metrics(data, 0, count), (1000, 100))
  assert_eq(glyph_metrics(data, 1, count), (1000, -1))
  assert_eq(glyph_metrics(data, 2, count), (1000, 50))
}

///|
test "vertical phantom overflow is refused before serializing output" {
  let source = vertical_test_tables()
  source["vmtx"] = b"\xff\xff\x00\x64"
  let glyph = parse_font_glyph(source["glyf"], 500, 0, 1, Ref(0), 1000)
  let data = b"\x00\x01\x00\x0a\x00\x06\xa0\x00\x40\x00\x01\x00\x05\x80\x00\x01"
  let table : GvarTable = { data, offsets: [0, 16], shared: [], axis_count: 1, }
  assert_true(
    try {
      ignore(
        vary_glyph(glyph, table, 0, [1.0], Ref(0), 1000, Some((65535, 100))),
      )
      false
    } catch {
      Invalid(_) => true
      _ => false
    },
  )
}
