///|
fn layout_test_gdef() -> Bytes raise FontError {
  let out = Array::make(18, (0 : Byte))
  set_u32(out, 0, 0x00010003U)
  set_u16(out, 4, 18)
  set_u16(out, 8, 26)
  set_u32(out, 14, 54U)
  for value in [1, 0, 1, 2, 6, 1, 12, 1, 1, 0, 1, 4, 3, 200, 6, 0, 0, 0x8000] {
    push_u16(out, value)
  }
  for byte in metric_test_store() {
    out.push(byte)
  }
  Bytes::from_array(out[:])
}

///|
test "GDEF caret variations freeze with class data and deterministic static reload" {
  let tables = api_fixture_tables()
  tables["GDEF"] = layout_test_gdef()
  let original = build_sfnt(tables, 100000)
  let font = Font::parse(original)
  for
    (weight, expected) in [
      (100.0, 200),
      (400.0, 200),
      (550.0, 250),
      (700.0, 300),
    ] {
    let output = font.instantiate({ "wght": weight }).to_bytes()
    let after = parse_sfnt(output, 100000)
    let data = after["GDEF"]
    assert_eq(read_uint32(data, 0), 0x00010000U)
    let class_at = read_u16(data, 4)
    assert_eq(read_u16(data, class_at + 6), 2)
    let list = read_u16(data, 8)
    let ligature = list + read_u16(data, list + 4)
    let caret = ligature + read_u16(data, ligature + 2)
    assert_eq(read_u16(data, caret), 1)
    assert_eq(read_i16(data, caret + 2), expected)
    assert_eq(output, font.instantiate({ "wght": weight }).to_bytes())
    assert_eq(build_sfnt(after, 100000), output)
    ignore(inspect_font(output))
  }
  assert_eq(parse_sfnt(original, 100000)["GDEF"], tables["GDEF"])
}

///|
test "GDEF malformed stores, offsets, coverage and carets refuse atomically" {
  let valid = layout_test_gdef()
  for length in 0..<valid.length() {
    let tables = api_fixture_tables()
    tables["GDEF"] = valid[0:length].to_owned()
    assert_true(
      try {
        ignore(Font::parse(build_sfnt(tables, 100000)).instantiate({}))
        false
      } catch {
        Invalid(_) | Limit(_) => true
        _ => false
      },
    )
  }
  for (offset, value) in [(18, 4), (32, 4), (36, 1), (42, 9), (52, 4)] {
    let tables = api_fixture_tables()
    let bytes = byte_array(valid)
    set_u16(bytes, offset, value)
    tables["GDEF"] = Bytes::from_array(bytes[:])
    assert_true(
      try {
        ignore(Font::parse(build_sfnt(tables, 100000)).instantiate({}))
        false
      } catch {
        _ => true
      },
    )
  }
  let tables = api_fixture_tables()
  let bytes = byte_array(valid)
  set_i16(bytes, 44, 32760)
  tables["GDEF"] = Bytes::from_array(bytes[:])
  let font = Font::parse(build_sfnt(tables, 100000))
  let expected = font.instantiate({}).to_bytes()
  assert_true(
    try {
      ignore(font.instantiate({ "wght": 700.0 }))
      false
    } catch {
      Invalid(detail) => detail.contains("ligature caret")
      _ => false
    },
  )
  assert_eq(font.instantiate({}).to_bytes(), expected)
  assert_true(
    try {
      ignore(font.instantiate({}, work_limit=1))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
}

///|
test "ordinary Device adjustments are preserved and layout relocation cannot truncate" {
  let data = b"\x00\x03\x00\xc8\x00\x06\x00\x09\x00\x0a\x00\x01\x70\x00"
  let ctx : LayoutContext = {
    data,
    glyphs: 1,
    store: None,
    work: Ref(0),
    limit: 1000,
    deltas: Ref(0),
  }
  let block = gdef_caret(ctx, 0)
  assert_eq(serialize_layout(block, ctx, 1000), data)
  let root = layout_block(65536)
  layout_link(root, 0, layout_block(2))
  let limited : LayoutContext = { ..ctx, work: Ref(0), limit: 100000, }
  assert_true(
    try {
      ignore(serialize_layout(root, limited, 100000))
      false
    } catch {
      Limit(detail) => detail.contains("16-bit")
      _ => false
    },
  )
  assert_true(
    try {
      ignore(serialize_layout(block, ctx, 4))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
}
