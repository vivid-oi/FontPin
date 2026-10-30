///|
fn context_test_bytes(format : Int32, chained : Bool) -> Bytes raise FontError {
  let coverage = layout_block(6)
  for (p, n) in [(0, 1), (2, 1), (4, 0)] {
    set_u16(coverage.data, p, n)
  }
  let root = if format == 3 {
    let values = if chained {
      [3, 1, 0, 2, 0, 0, 1, 0, 1, 1, 0]
    } else {
      [3, 2, 1, 0, 0, 1, 0]
    }
    let root = layout_block(values.length() * 2)
    for i, n in values {
      set_u16(root.data, i * 2, n)
    }
    for field in (if chained { [4, 8, 10, 14] } else { [6, 8] }) {
      layout_link(root, field, coverage)
    }
    root
  } else {
    let count_field = if format == 1 { 4 } else if chained { 10 } else { 6 }
    let count = if format == 1 { 1 } else { 2 }
    let root = layout_block(count_field + 2 + count * 2)
    set_u16(root.data, 0, format)
    set_u16(root.data, count_field, count)
    layout_link(root, 2, coverage)
    if format == 2 {
      let class_def = layout_block(8)
      for (p, n) in [(0, 1), (2, 0), (4, 1), (6, 1)] {
        set_u16(class_def.data, p, n)
      }
      for field in (if chained { [4, 6, 8] } else { [4] }) {
        layout_link(root, field, class_def)
      }
    }
    let rule = layout_block(if chained { 18 } else { 10 })
    let values = if chained {
      [1, 1, 2, 1, 1, 1, 1, 1, 0]
    } else {
      [2, 1, 1, 1, 0]
    }
    for i, n in values {
      set_u16(rule.data, i * 2, n)
    }
    let set = layout_block(4)
    set_u16(set.data, 0, 1)
    layout_link(set, 2, rule)
    layout_link(root, count_field + count * 2, set)
    root
  }
  serialize_layout(root, layout_test_context(b""), 10000)
}

///|
test "all six contextual positioning formats round trip and validate every truncation" {
  for chained in [false, true] {
    for format in [1, 2, 3] {
      let source = context_test_bytes(format, chained)
      let ctx = layout_test_context(source)
      assert_eq(
        serialize_layout(gpos_context(ctx, 0, chained, 1), ctx, 10000),
        source,
      )
      for length in 0..<source.length() {
        assert_true(
          try {
            ignore(
              gpos_context(
                layout_test_context(source[0:length].to_owned()),
                0,
                chained,
                1,
              ),
            )
            false
          } catch {
            _ => true
          },
        )
      }
      assert_true(
        try {
          ignore(gpos_context(layout_test_context(source), 0, chained, 0))
          false
        } catch {
          Invalid(message) => message.contains("lookup")
          _ => false
        },
      )
      let limited = layout_test_context(source)
      assert_true(
        try {
          ignore(gpos_context({ ..limited, limit: 2, }, 0, chained, 1))
          false
        } catch {
          Limit(_) => true
          _ => false
        },
      )
    }
  }
}

///|
test "invalid contextual sequence and glyph references refuse without changing static layout bytes" {
  let bytes = byte_array(context_test_bytes(3, false))
  set_u16(bytes, 10, 2)
  assert_true(
    try {
      ignore(
        gpos_context(
          layout_test_context(Bytes::from_array(bytes[:])),
          0,
          false,
          1,
        ),
      )
      false
    } catch {
      Invalid(message) => message.contains("sequence")
      _ => false
    },
  )
  let tables = api_fixture_tables()
  // A dangling VariationIndex without a GDEF store must never pass as static.
  tables["GPOS"] = layout_test_gpos()
  let font = Font::parse(build_sfnt(tables, 100000))
  assert_true(
    try {
      ignore(font.instantiate({}))
      false
    } catch {
      Invalid(_) | Unsupported(_) => true
      _ => false
    },
  )
  let ctx = layout_test_context(layout_test_gpos())
  let static_gpos = freeze_gpos(ctx, 0, 10000)
  tables["GPOS"] = static_gpos
  let source = build_sfnt(tables, 100000)
  let output = Font::parse(source).instantiate({}).to_bytes()
  assert_eq(parse_sfnt(output, 100000)["GPOS"], static_gpos)
  assert_eq(parse_sfnt(source, 100000)["GPOS"], static_gpos)
}
