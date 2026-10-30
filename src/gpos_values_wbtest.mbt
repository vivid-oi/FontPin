///|
fn layout_test_gpos() -> Bytes raise FontError {
  let out : Array[Byte] = []
  push_u32(out, 0x00010000U)
  for
    value in [
      10, 12, 14, 0, 0, 1, 4, 1, 0, 1, 8, 1, 8, 64, 14, 1, 1, 0, 0, 0, 0x8000,
    ] {
    push_u16(out, value)
  }
  Bytes::from_array(out[:])
}

///|
fn layout_test_context(
  data : Bytes,
  glyphs~ : Int32 = 2,
  position~ : Double = 0.5,
) -> LayoutContext raise FontError {
  {
    data,
    glyphs,
    store: Some(variation_store(metric_test_store(), 0, [position])),
    work: Ref(0),
    limit: 10000,
    deltas: Ref(0),
  }
}

///|
test "SinglePos missing base fields become static values and extension relocations reload" {
  let tables = api_fixture_tables()
  tables["GDEF"] = layout_test_gdef()
  tables["GPOS"] = layout_test_gpos()
  let source = build_sfnt(tables, 100000)
  let font = Font::parse(source)
  for (weight, expected) in [(400.0, 0), (550.0, 50), (700.0, 100)] {
    let bytes = font.instantiate({ "wght": weight }).to_bytes()
    let result = parse_sfnt(bytes, 100000)
    let data = result["GPOS"]
    let list = read_u16(data, 8)
    let lookup = list + read_u16(data, list + 2)
    assert_eq(read_u16(data, lookup), 9)
    let extension = lookup + read_u16(data, lookup + 6)
    assert_eq(read_u16(data, extension + 2), 1)
    let single = extension + read_u32(data, extension + 4)
    assert_eq(read_u16(data, single + 4), 4)
    assert_eq(read_i16(data, single + 6), expected)
    assert_eq(gdef_version(result["GDEF"]), 0)
    assert_eq(bytes, font.instantiate({ "wght": weight }).to_bytes())
    assert_eq(build_sfnt(result, 100000), bytes)
  }
  assert_eq(parse_sfnt(source, 100000)["GPOS"], tables["GPOS"])
}

///|
test "PairPos format 1 Device offsets use PairSet origin and both value records survive" {
  let out : Array[Byte] = []
  for value in [1, 12, 64, 0, 1, 18, 1, 1, 0, 1, 1, 6, 0, 0, 0x8000] {
    push_u16(out, value)
  }
  let ctx = layout_test_context(Bytes::from_array(out[:]))
  let frozen = serialize_layout(gpos_pair(ctx, 0), ctx, 10000)
  assert_eq(read_u16(frozen, 4), 4)
  assert_eq(read_u16(frozen, 6), 0)
  let set = read_u16(frozen, 10)
  assert_eq(read_u16(frozen, set + 2), 1)
  assert_eq(read_i16(frozen, set + 4), 50)
  assert_eq(ctx.deltas.val, 1)
}

///|
test "SinglePos arrays and PairPos class matrices retain complete values and class zero" {
  let single : Array[Byte] = []
  for value in [2, 12, 64, 2, 20, 26, 1, 2, 0, 1, 0, 0, 0x8000, 0, 1, 0x8000] {
    push_u16(single, value)
  }
  let ctx = layout_test_context(Bytes::from_array(single[:]))
  let frozen = serialize_layout(gpos_single(ctx, 0), ctx, 10000)
  assert_eq(read_i16(frozen, 8), 50)
  assert_eq(read_i16(frozen, 10), -25)
  let pair : Array[Byte] = []
  for
    value in [
      2, 24, 64, 0, 30, 40, 2, 2, 50, 50, 50, 50, 1, 1, 0, 1, 0, 2, 0, 1, 1, 0, 2,
      0, 1, 0, 0, 0x8000,
    ] {
    push_u16(pair, value)
  }
  let ctx = layout_test_context(Bytes::from_array(pair[:]))
  let frozen = serialize_layout(gpos_pair(ctx, 0), ctx, 10000)
  assert_eq(read_u16(frozen, 12), 2)
  assert_eq(read_u16(frozen, 14), 2)
  for i in 0..<4 {
    assert_eq(read_i16(frozen, 16 + i * 2), 50)
  }
}

///|
test "GPOS malformed value data, flags, recursive extensions and overflow are refused" {
  let valid = layout_test_gpos()
  for length in 0..<valid.length() {
    let ctx = layout_test_context(valid[0:length].to_owned())
    assert_true(
      try {
        ignore(freeze_gpos(ctx, 0, 10000))
        false
      } catch {
        _ => true
      },
    )
  }
  for (field, value) in [(18, 10), (20, 0x20), (30, 0x100), (34, 4), (44, 9)] {
    let bytes = byte_array(valid)
    set_u16(bytes, field, value)
    assert_true(
      try {
        ignore(
          freeze_gpos(
            layout_test_context(Bytes::from_array(bytes[:])),
            0,
            10000,
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let recursive = byte_array(valid)
  set_u16(recursive, 18, 9)
  set_u16(recursive, 28, 9)
  assert_true(
    try {
      ignore(
        freeze_gpos(
          layout_test_context(Bytes::from_array(recursive[:])),
          0,
          10000,
        ),
      )
      false
    } catch {
      Invalid(detail) => detail.contains("recursive")
      _ => false
    },
  )
  let ctx = layout_test_context(valid)
  assert_true(
    try {
      ignore(freeze_gpos({ ..ctx, work: Ref(0), limit: 1, }, 0, 10000))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  let value : Array[Byte] = []
  for number in [1, 10, 68, 32760, 16, 1, 1, 0, 0, 0, 0x8000] {
    push_u16(value, number)
  }
  assert_true(
    try {
      ignore(
        gpos_single(
          layout_test_context(Bytes::from_array(value[:]), position=1.0),
          0,
        ),
      )
      false
    } catch {
      Invalid(detail) => detail.contains("overflow")
      _ => false
    },
  )
}
