///|
fn anchor_test_bytes(kind : Int32) -> Bytes raise FontError {
  let root = layout_block(if kind == 3 { 10 } else { 12 })
  set_u16(root.data, 0, 1)
  let cov = layout_block(6)
  for (field, value) in [(0, 1), (2, 1), (4, 0)] {
    set_u16(cov.data, field, value)
  }
  layout_link(root, 2, cov)
  let anchor = layout_block(10)
  set_u16(anchor.data, 0, 3)
  set_i16(anchor.data, 2, 100)
  set_i16(anchor.data, 4, -100)
  let device = layout_block(6)
  set_u16(device.data, 4, 0x8000)
  layout_link(anchor, 6, device)
  if kind == 3 {
    set_u16(root.data, 4, 1)
    layout_link(root, 6, anchor)
  } else {
    layout_link(root, 4, cov)
    set_u16(root.data, 6, 2)
    let marks = layout_block(6)
    set_u16(marks.data, 0, 1)
    set_u16(marks.data, 2, 1)
    layout_link(marks, 4, anchor)
    layout_link(root, 8, marks)
    let matrix = layout_block(if kind == 5 { 10 } else { 6 })
    set_u16(matrix.data, 0, if kind == 5 { 2 } else { 1 })
    layout_link(matrix, 4, anchor)
    if kind == 5 {
      layout_link(matrix, 8, anchor)
      let ligatures = layout_block(4)
      set_u16(ligatures.data, 0, 1)
      layout_link(ligatures, 2, matrix)
      layout_link(root, 10, ligatures)
    } else {
      layout_link(root, 10, matrix)
    }
  }
  serialize_layout(root, layout_test_context(b""), 10000)
}

///|
test "cursive and all mark anchor arrays freeze and round trip without losing null anchors" {
  for kind in [3, 4, 5, 6] {
    let source = anchor_test_bytes(kind)
    let ctx = layout_test_context(source)
    let block = gpos_subtable(ctx, kind, 0, 1)
    let frozen = serialize_layout(block, ctx, 10000)
    let ctx2 = layout_test_context(frozen)
    assert_eq(
      serialize_layout(gpos_subtable(ctx2, kind, 0, 1), ctx2, 10000),
      frozen,
    )
    assert_eq(ctx2.deltas.val, 0)
    let a = if kind == 3 {
      read_u16(frozen, 6)
    } else {
      let marks = read_u16(frozen, 8)
      marks + read_u16(frozen, marks + 4)
    }
    assert_eq(read_u16(frozen, a), 1)
    assert_eq(read_i16(frozen, a + 2), 150)
    assert_eq(read_i16(frozen, a + 4), -100)
    if kind == 3 {
      assert_eq(read_u16(frozen, 8), 0)
    }
    for length in 0..<source.length() {
      let truncated = layout_test_context(source[0:length].to_owned())
      assert_true(
        try {
          ignore(gpos_subtable(truncated, kind, 0, 1))
          false
        } catch {
          _ => true
        },
      )
    }
  }
}

///|
test "anchor formats retain point references and ordinary Device adjustments" {
  let point = b"\x00\x02\x00\x0a\xff\xf6\x00\x03"
  let ctx = layout_test_context(point)
  assert_eq(serialize_layout(layout_anchor(ctx, 0), ctx, 1000), point)
  let device = b"\x00\x03\x00\x0a\xff\xf6\x00\x0a\x00\x00\x00\x0c\x00\x0c\x00\x01\x40\x00"
  let ctx = layout_test_context(device)
  assert_eq(serialize_layout(layout_anchor(ctx, 0), ctx, 1000), device)
  let bad = byte_array(anchor_test_bytes(4))
  let mark = read_u16(Bytes::from_array(bad[:]), 8)
  set_u16(bad, mark + 2, 2)
  assert_true(
    try {
      ignore(gpos_marks(layout_test_context(Bytes::from_array(bad[:])), 0, 4))
      false
    } catch {
      Invalid(_) => true
      _ => false
    },
  )
  let overflow = b"\x00\x03\x7f\xff\x00\x00\x00\x0a\x00\x00\x00\x00\x00\x00\x80\x00"
  assert_true(
    try {
      ignore(layout_anchor(layout_test_context(overflow), 0))
      false
    } catch {
      Invalid(_) => true
      _ => false
    },
  )
  let valid = anchor_test_bytes(5)
  let ctx = layout_test_context(valid)
  assert_true(
    try {
      ignore(gpos_marks({ ..ctx, limit: 1, }, 0, 5))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  // An error cannot mutate source bytes or poison the following valid operation.
  assert_eq(valid, anchor_test_bytes(5))
  ignore(gpos_marks(layout_test_context(valid), 0, 5))
}
