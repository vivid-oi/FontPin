///|
fn feature_test_bytes() -> Bytes raise FontError {
  let root = layout_block(14)
  set_u32(root.data, 0, 0x00010001U)
  layout_link(root, 4, layout_block(2))
  let features = layout_block(8)
  set_u16(features.data, 0, 1)
  for i in 0..<4 {
    features.data[2 + i] = b"kern"[i]
  }
  let base = layout_block(6)
  set_u16(base.data, 2, 1)
  layout_link(features, 6, base)
  layout_link(root, 6, features)
  let lookups = layout_block(6)
  set_u16(lookups.data, 0, 2)
  layout_link(root, 8, lookups)
  let variations = layout_block(24)
  set_u32(variations.data, 0, 0x00010000U)
  set_u32(variations.data, 4, 2U)
  for i in 0..<2 {
    let conditions = layout_block(6)
    set_u16(conditions.data, 0, 1)
    let condition = layout_block(8)
    set_u16(condition.data, 0, 1)
    set_i16(condition.data, 4, if i == 0 { 8192 } else { 0 })
    set_i16(condition.data, 6, 16384)
    layout_link(conditions, 2, condition, wide=true)
    layout_link(variations, 8 + i * 8, conditions, wide=true)
    let substitution = layout_block(12)
    set_u32(substitution.data, 0, 0x00010000U)
    set_u16(substitution.data, 4, 1)
    let alternate = layout_block(if i == 0 { 6 } else { 8 })
    set_u16(alternate.data, 2, if i == 0 { 1 } else { 2 })
    set_u16(alternate.data, 4, 1)
    if i == 1 {
      set_u16(alternate.data, 6, 0)
    }
    layout_link(substitution, 8, alternate, wide=true)
    layout_link(variations, 12 + i * 8, substitution, wide=true)
  }
  layout_link(root, 10, variations, wide=true)
  serialize_layout(root, layout_test_context(b""), 10000)
}

///|
test "conditional feature selection uses inclusive ranges and first match while retaining lookup payloads" {
  let source = feature_test_bytes()
  let lookup = read_u16(source, 8)
  for
    (position, expected) in [
      (-1.0, None),
      (0.0, Some(1)),
      (0.49993896484375, Some(1)),
      (0.5, Some(0)),
      (1.0, Some(0)),
    ] {
    let (output, selected) = freeze_feature_variations(
      layout_test_context(source),
      [position],
      10000,
    )
    assert_eq(selected, expected)
    assert_eq(read_uint32(output, 0), 0x00010000U)
    let feature_list = read_u16(output, 6)
    let feature = feature_list + read_u16(output, feature_list + 6)
    assert_eq(
      read_u16(output, feature + 2),
      if expected == Some(1) {
        2
      } else {
        1
      },
    )
    assert_eq(
      read_u16(output, feature + 4),
      if expected is Some(_) {
        1
      } else {
        0
      },
    )
    let output_lookup = read_u16(output, 8)
    assert_eq(
      output[output_lookup:output_lookup + 6].to_owned(),
      source[lookup:lookup + 6].to_owned(),
    )
    let (again, none) = freeze_feature_variations(
      layout_test_context(output),
      [position],
      10000,
    )
    assert_eq(again, output)
    assert_eq(none, None)
  }
  assert_eq(source, feature_test_bytes())
}

///|
test "conditional layout validates unmatched branches, null conditions, truncation and budgets" {
  let source = feature_test_bytes()
  for length in 0..<source.length() {
    assert_true(
      try {
        ignore(
          freeze_feature_variations(
            layout_test_context(source[0:length].to_owned()),
            [-1.0],
            10000,
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let variations = read_u32(source, 10)
  let conditions = variations + read_u32(source, variations + 8)
  let condition = conditions + read_u32(source, conditions + 2)
  let substitution = variations + read_u32(source, variations + 12)
  for
    (field, value) in [
      (condition, 2),
      (condition + 2, 1),
      (condition + 4, 20000),
      (substitution + 6, 1),
    ] {
    let bad = byte_array(source)
    set_u16(bad, field, value)
    assert_true(
      try {
        ignore(
          freeze_feature_variations(
            layout_test_context(Bytes::from_array(bad[:])),
            [-1.0],
            10000,
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let unconditional = byte_array(source)
  set_u32(unconditional, variations + 8, 0U)
  let (_, selected) = freeze_feature_variations(
    layout_test_context(Bytes::from_array(unconditional[:])),
    [-1.0],
    10000,
  )
  assert_eq(selected, Some(0))
  let ctx = layout_test_context(source)
  assert_true(
    try {
      ignore(freeze_feature_variations({ ..ctx, limit: 1, }, [0.5], 10000))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(
        freeze_feature_variations(
          layout_test_context(source),
          [0.5],
          source.length(),
        ),
      )
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  ignore(freeze_feature_variations(layout_test_context(source), [0.5], 10000))
}
