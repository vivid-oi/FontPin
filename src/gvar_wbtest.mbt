///|
test "gvar packed deltas: zero, signed byte, signed word and truncation" {
  let cursor : GvarCursor = {
    data: b"\x81\x01\xff\x7f\x41\x80\x00\x7f\xff",
    pos: 0,
    end: 9,
  }
  assert_eq(packed_deltas(cursor, 6), [0.0, 0.0, -1.0, 127.0, -32768.0, 32767.0])
  assert_eq(cursor.pos, 9)
  let bad : GvarCursor = { data: b"\x40\x00", pos: 0, end: 2, }
  let rejected = try {
    ignore(packed_deltas(bad, 1))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  let overrun : GvarCursor = { data: b"\x81", pos: 0, end: 1, }
  let rejected = try {
    ignore(packed_deltas(overrun, 1))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "gvar point runs validate monotonic references and glyph boundaries" {
  let cursor : GvarCursor = { data: b"\x03\x02\x00\x02\x03", pos: 0, end: 5, }
  assert_eq(packed_points(cursor, 6), Some([0, 2, 5]))
  let duplicate : GvarCursor = { data: b"\x02\x01\x01\x00", pos: 0, end: 4, }
  assert_eq(packed_points(duplicate, 6), Some([1, 1]))
  let outside : GvarCursor = { data: b"\x01\x00\x06", pos: 0, end: 3, }
  let rejected = try {
    ignore(packed_points(outside, 6))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  let all : GvarCursor = { data: b"\x00", pos: 0, end: 1, }
  assert_eq(packed_points(all, 100), None)
}

///|
test "tuple scalar uses default inferred bounds, intermediate peaks and products" {
  assert_eq(tuple_scalar([0.5], [1.0], None, None), 0.5)
  assert_eq(tuple_scalar([0.75], [0.5], None, None), 0.0)
  assert_eq(tuple_scalar([-0.5], [1.0], None, None), 0.0)
  assert_eq(tuple_scalar([0.75], [0.5], Some([0.0]), Some([1.0])), 0.5)
  assert_eq(tuple_scalar([0.5, -0.25], [1.0, -1.0], None, None), 0.125)
  assert_eq(tuple_scalar([1.0, 0.9], [1.0, 0.0], None, None), 1.0)
}

///|
test "IUP wraps contours, clamps endpoints and leaves phantom points alone" {
  let original = [0.0, 25.0, 50.0, 75.0, 100.0, 500.0]
  let deltas = [10.0, 0.0, 0.0, 0.0, 30.0, 0.0]
  iup_contours(original, deltas, [true, false, false, false, true, false], [4])
  assert_eq(deltas, [10.0, 15.0, 20.0, 25.0, 30.0, 0.0])
  let one = [0.0, 12.0, 0.0, 0.0]
  iup_contours([0.0, 1.0, 2.0, 3.0], one, [false, true, false, false], [2])
  assert_eq(one, [12.0, 12.0, 12.0, 0.0])
  assert_eq(iup_value(1.0, 2.0, 3.0, 2.0, 4.0), 0.0)
  assert_eq(iup_value(1.0, 2.0, 3.0, 2.0, 3.0), 3.0)
  let ring = [0.0, 10.0, 0.0, 20.0]
  iup_contours([50.0, 0.0, 50.0, 100.0], ring, [false, true, false, true], [3])
  assert_eq(ring, [15.0, 10.0, 15.0, 20.0])
}

///|
fn glyph_fixture_tables() -> Map[String, Bytes] raise FontError {
  let head = Array::make(54, (0 : Byte))
  set_u16(head, 50, 1)
  let maxp = Array::make(32, (0 : Byte))
  set_u16(maxp, 4, 1)
  let hhea = Array::make(36, (0 : Byte))
  set_u16(hhea, 34, 1)
  let gvar : Array[Byte] = []
  push_u16(gvar, 1)
  push_u16(gvar, 0)
  push_u16(gvar, 1)
  push_u16(gvar, 0)
  push_u32(gvar, 28U)
  push_u16(gvar, 1)
  push_u16(gvar, 1)
  push_u32(gvar, 28U)
  push_u32(gvar, 0U)
  push_u32(gvar, 19U)
  push_u16(gvar, 1)
  push_u16(gvar, 10)
  push_u16(gvar, 9)
  push_u16(gvar, 32768)
  push_u16(gvar, 16384)
  for byte in b"\x06\x0a\x14\x1e\x00\x64\x00\x00\x86" {
    gvar.push(byte)
  }
  {
    "head": Bytes::from_array(head[:]),
    "maxp": Bytes::from_array(maxp[:]),
    "hhea": Bytes::from_array(hhea[:]),
    "hmtx": b"\x01\xf4\x00\x00",
    "loca": b"\x00\x00\x00\x00\x00\x00\x00\x1e",
    "glyf": b"\x00\x01\x00\x00\x00\x00\x00\x64\x00\x64\x00\x02\x00\x00\x01\x01\x01\x00\x00\x00\x64\xff\x9c\x00\x00\x00\x00\x00\x64\x00",
    "gvar": Bytes::from_array(gvar[:]),
  }
}

///|
test "full outline instancing preserves contours and updates phantom metrics" {
  let tables = glyph_fixture_tables()
  let result = instantiate_glyphs(tables, [1.0], 1000)
  assert_eq(result.glyph_count, 1)
  assert_eq(result.x_min, 10)
  assert_eq(result.x_max, 120)
  assert_eq(result.y_min, 0)
  assert_eq(result.y_max, 100)
  assert_eq(read_u16(result.hmtx, 0), 600)
  assert_eq(read_i16(result.hmtx, 2), 10)
  let glyph = parse_font_glyph(result.glyf, 600, 10, 1, Ref(0), 1000)
  match glyph.body {
    Simple(ends~, xs~, ys~, flags~, ..) => {
      assert_eq(ends, [2])
      assert_eq(xs, [10, 120, 30])
      assert_eq(ys, [0, 0, 100])
      assert_eq(flags[0] & 64, 64)
    }
    _ => fail("expected simple triangle")
  }
  let default = instantiate_glyphs(tables, [0.0], 1000)
  assert_eq(read_u16(default.hmtx, 0), 500)
  assert_eq(default.x_max, 100)
  let halfway = instantiate_glyphs(tables, [0.5], 1000)
  assert_eq(read_u16(halfway.hmtx, 0), 550)
  assert_eq(halfway.x_max, 110)
  assert_eq(result.glyf, instantiate_glyphs(tables, [1.0], 1000).glyf)
  let rejected = try {
    ignore(instantiate_glyphs(tables, [1.0], 2))
    false
  } catch {
    Limit(_) => true
    _ => false
  }
  assert_true(rejected)
  // A failed request leaves the immutable source and subsequent output intact.
  assert_eq(result.glyf, instantiate_glyphs(tables, [1.0], 1000).glyf)
}

///|
test "composite topology rejects cycles and supports translated components" {
  let leaf : FontGlyph = {
    body: Simple(ends=[0], flags=[1], xs=[10], ys=[20], instructions=b""),
    x_min: 10,
    y_min: 20,
    x_max: 10,
    y_max: 20,
    advance: 100,
    lsb: 0,
  }
  let component : GlyphComponent = {
    flags: 3,
    glyph: 0,
    x: 5,
    y: -3,
    xx: 1.0,
    xy: 0.0,
    yx: 0.0,
    yy: 1.0,
    transform: b"",
  }
  let parent : FontGlyph = {
    body: Composite(components=[component, component], instructions=b"\x00"),
    x_min: 0,
    y_min: 0,
    x_max: 0,
    y_max: 0,
    advance: 100,
    lsb: 0,
  }
  let glyphs = [leaf, parent]
  calculate_glyph_bounds(glyphs, 1, Ref(0), 100)
  assert_eq(parent.x_min, 15)
  assert_eq(parent.y_min, 17)
  let encoded = encode_font_glyph(parent)
  let loaded = parse_font_glyph(encoded, 100, 0, 2, Ref(0), 100)
  match loaded.body {
    Composite(instructions~, components~) => {
      assert_eq(instructions, b"\x00")
      assert_eq(components[0].flags & 1024, 1024)
      assert_eq(components[1].flags & 1024, 0)
    }
    _ => fail("expected composite")
  }
  let cyclic : FontGlyph = {
    body: Composite(components=[component], instructions=b""),
    x_min: 0,
    y_min: 0,
    x_max: 0,
    y_max: 0,
    advance: 100,
    lsb: 0,
  }
  let rejected = try {
    ignore(collect_glyph_points([cyclic], 0, [], Ref(0), 100))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "duplicate explicit point deltas are accumulated before IUP" {
  let data = b"\x00\x01\x00\x0a\x00\x08\xa0\x00\x40\x00\x02\x01\x00\x00\x01\x0a\x14\x81"
  let table : GvarTable = { data, offsets: [0, 18], shared: [], axis_count: 1, }
  let xs = [0.0, 0.0, 100.0, 0.0, 0.0]
  let ys = [0.0, 0.0, 0.0, 0.0, 0.0]
  apply_gvar(table, 0, [1.0], xs, ys, [0], Ref(0), 100)
  assert_eq(xs, [30.0, 0.0, 100.0, 0.0, 0.0])
}

///|
test "zero-contour glyphs accept header-only form and preserve phantom instructions" {
  let header = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let glyph = parse_font_glyph(header, 500, 20, 1, Ref(0), 100)
  match glyph.body {
    Simple(ends~, instructions~, ..) => {
      assert_true(ends.is_empty())
      assert_eq(instructions, b"")
    }
    _ => fail("expected zero-contour simple glyph")
  }
  let hinted = parse_font_glyph(
    header + b"\x00\x01\x00",
    500,
    20,
    1,
    Ref(0),
    100,
  )
  let encoded = encode_font_glyph(hinted)
  let loaded = parse_font_glyph(encoded, 500, 20, 1, Ref(0), 100)
  match loaded.body {
    Simple(instructions~, ..) => assert_eq(instructions, b"\x00")
    _ => fail("expected zero-contour simple glyph")
  }
  let rejected = try {
    ignore(parse_font_glyph(header + b"\x00", 500, 20, 1, Ref(0), 100))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "empty composite expansion consumes work budget" {
  let leaf : FontGlyph = {
    body: Empty,
    x_min: 0,
    y_min: 0,
    x_max: 0,
    y_max: 0,
    advance: 100,
    lsb: 0,
  }
  let glyphs = [leaf]
  for gid in 1..<10 {
    let component : GlyphComponent = {
      flags: 3,
      glyph: gid - 1,
      x: 0,
      y: 0,
      xx: 1.0,
      xy: 0.0,
      yx: 0.0,
      yy: 1.0,
      transform: b"",
    }
    glyphs.push({
      body: Composite(components=[component, component], instructions=b""),
      x_min: 0,
      y_min: 0,
      x_max: 0,
      y_max: 0,
      advance: 100,
      lsb: 0,
    })
  }
  let rejected = try {
    ignore(collect_glyph_points(glyphs, 9, [], Ref(0), 100))
    false
  } catch {
    Limit(_) => true
    _ => false
  }
  assert_true(rejected)
  let (xs, ys) = collect_glyph_points(glyphs, 9, [], Ref(0), 1023)
  assert_true(xs.is_empty())
  assert_true(ys.is_empty())
}

///|
test "coordinate rounding validates before narrowing to Int32" {
  assert_eq(round_glyph_coordinate(-32768.5), -32768)
  assert_eq(round_glyph_coordinate(32767.499), 32767)
  for value in [-32768.501, 32767.5, 4294967296.0, -4294967296.0] {
    let rejected = try {
      ignore(round_glyph_coordinate(value))
      false
    } catch {
      Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "glyph tables reject unreferenced data and accept zero alignment" {
  let source = glyph_fixture_tables()
  assert_true(!source.contains("HVAR"))
  let expected = instantiate_glyphs(source, [0.5], 1000)
  let metric_tail = source.copy()
  metric_tail["hmtx"] = source["hmtx"] + b"\x00"
  let loca_tail = source.copy()
  loca_tail["loca"] = source["loca"] + b"\x00\x00\x00\x00"
  let nonzero_tail = source.copy()
  nonzero_tail["glyf"] = source["glyf"] + b"\x01"
  let excess_zero_tail = source.copy()
  excess_zero_tail["glyf"] = source["glyf"] + b"\x00\x00\x00\x00"
  let prefix = source.copy()
  prefix["glyf"] = b"\x00\x00" + source["glyf"]
  prefix["loca"] = b"\x00\x00\x00\x02\x00\x00\x00\x20"
  for
    invalid in [metric_tail, loca_tail, nonzero_tail, excess_zero_tail, prefix] {
    let rejected = try {
      ignore(instantiate_glyphs(invalid, [0.5], 1000))
      false
    } catch {
      Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
  for padding in [b"\x00", b"\x00\x00", b"\x00\x00\x00"] {
    let padded = source.copy()
    padded["glyf"] = source["glyf"] + padding
    assert_eq(instantiate_glyphs(padded, [0.5], 1000).glyf, expected.glyf)
  }
  // Per-glyph alignment remains valid when loca references that padding.
  let glyph_padding = source.copy()
  glyph_padding["glyf"] = source["glyf"] + b"\x00\x00"
  glyph_padding["loca"] = b"\x00\x00\x00\x00\x00\x00\x00\x20"
  assert_eq(instantiate_glyphs(glyph_padding, [0.5], 1000).glyf, expected.glyf)
  // The malformed requests have not mutated the reusable source.
  assert_eq(instantiate_glyphs(source, [0.5], 1000).glyf, expected.glyf)
}
