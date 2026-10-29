///|
fn attachment_test_glyphs() -> Array[FontGlyph] raise FontError {
  let leaf = parse_font_glyph(
    glyph_fixture_tables()["glyf"],
    500,
    0,
    2,
    Ref(0),
    1000,
  )
  let translated : GlyphComponent = {
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
  let aligned : GlyphComponent = {
    flags: 132,
    glyph: 0,
    x: 1,
    y: 2,
    xx: 0.5,
    xy: 0.25,
    yx: 0.125,
    yy: 1.0,
    transform: b"\x20\x00\x10\x00\x08\x00\x40\x00",
  }
  let parent : FontGlyph = {
    body: Composite(
      components=[translated, aligned],
      instructions=b"\xb0\x01\x21",
    ),
    x_min: 0,
    y_min: 0,
    x_max: 0,
    y_max: 0,
    advance: 900,
    lsb: 0,
  }
  [leaf, parent]
}

///|
test "point attachment transforms the child before aligning and ignores XY rounding flags" {
  let glyphs = attachment_test_glyphs()
  let (xs, ys) = collect_glyph_points(glyphs, 1, [], Ref(0), 1000)
  assert_eq(xs, [5.0, 105.0, 5.0, 92.5, 142.5, 105.0])
  assert_eq(ys, [-3.0, -3.0, 97.0, -103.0, -78.0, -3.0])
  calculate_glyph_bounds(glyphs, 1, Ref(0), 1000)
  let parent = glyphs[1]
  assert_eq(
    (parent.x_min, parent.y_min, parent.x_max, parent.y_max),
    (5, -103, 143, 97),
  )
  let loaded = parse_font_glyph(
    encode_font_glyph(parent),
    900,
    0,
    2,
    Ref(0),
    1000,
  )
  match loaded.body {
    Composite(components~, instructions~) => {
      assert_eq((components[1].x, components[1].y), (1, 2))
      assert_eq(components[1].flags & 2, 0)
      assert_eq(components[1].transform, b"\x20\x00\x10\x00\x08\x00\x40\x00")
      assert_eq(instructions, b"\xb0\x01\x21")
    }
    _ => fail("composite representation lost")
  }
  assert_eq(
    collect_glyph_points([glyphs[0], loaded], 1, [], Ref(0), 1000),
    (xs, ys),
  )
}

///|
test "point arguments decode unsigned in byte and word form and survive encoding" {
  let header = b"\xff\xff\x00\x00\x00\x00\x00\x64\x00\x64"
  let first = b"\x00\x23\x00\x00\x00\x00\x00\x00"
  for
    (record, a, b) in [
      (b"\x00\x00\x00\x00\xc8\xfa", 200, 250),
      (b"\x00\x01\x00\x00\x9c\x40\xff\xff", 40000, 65535),
    ] {
    let glyph = parse_font_glyph(
      header + first + record,
      900,
      0,
      2,
      Ref(0),
      100,
    )
    let loaded = parse_font_glyph(
      encode_font_glyph(glyph),
      900,
      0,
      2,
      Ref(0),
      100,
    )
    match loaded.body {
      Composite(components~, ..) =>
        assert_eq((components[1].x, components[1].y), (a, b))
      _ => fail("expected composite")
    }
  }
  assert_true(
    try {
      ignore(
        parse_font_glyph(
          header + b"\x00\x00\x00\x00\x00\x00",
          900,
          0,
          2,
          Ref(0),
          100,
        ),
      )
      false
    } catch {
      Invalid(detail) => detail.contains("first composite")
      _ => false
    },
  )
}

///|
test "parent gvar deltas on point-aligned components are ignored as specified" {
  let glyphs = attachment_test_glyphs()
  let data = b"\x00\x01\x00\x0a\x00\x0e\x80\x00\x40\x00\x05\x00\x7b\x00\x00\x00\x00\x05\x00\xb3\x00\x00\x00\x00"
  let table : GvarTable = {
    data,
    offsets: [0, 0, 24],
    shared: [],
    axis_count: 1,
  }
  ignore(vary_glyph(glyphs[1], table, 1, [1.0], Ref(0), 1000, None))
  match glyphs[1].body {
    Composite(components~, ..) => {
      assert_eq((components[0].x, components[0].y), (5, -3))
      assert_eq((components[1].x, components[1].y), (1, 2))
    }
    _ => fail("missing composite")
  }
  let (xs, _) = collect_glyph_points(glyphs, 1, [], Ref(0), 1000)
  assert_eq(xs[5], xs[1])
}

///|
test "unavailable attachment points refuse without panic and a valid glyph remains reusable" {
  let glyphs = attachment_test_glyphs()
  let expected = collect_glyph_points(glyphs, 1, [], Ref(0), 1000)
  guard glyphs[1].body is Composite(components~, ..) else {
    fail("missing composite")
  }
  for (a, b) in [(3, 2), (1, 3), (65535, 65535)] {
    components[1].x = a
    components[1].y = b
    assert_true(
      try {
        ignore(collect_glyph_points(glyphs, 1, [], Ref(0), 1000))
        false
      } catch {
        Unsupported(detail) => detail.contains("phantom-point alignment")
        _ => false
      },
    )
  }
  components[1].x = 1
  components[1].y = 2
  assert_eq(collect_glyph_points(glyphs, 1, [], Ref(0), 1000), expected)
  assert_true(
    try {
      ignore(collect_glyph_points(glyphs, 1, [], Ref(0), 2))
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
}

///|
test "nested composite attachment indexes flattened contour points" {
  let glyphs = attachment_test_glyphs()
  let nested : GlyphComponent = {
    flags: 3,
    glyph: 1,
    x: 10,
    y: 20,
    xx: 1.0,
    xy: 0.0,
    yx: 0.0,
    yy: 1.0,
    transform: b"",
  }
  let anchor : GlyphComponent = {
    flags: 0,
    glyph: 0,
    x: 5,
    y: 1,
    xx: 1.0,
    xy: 0.0,
    yx: 0.0,
    yy: 1.0,
    transform: b"",
  }
  glyphs.push({
    body: Composite(components=[nested, anchor], instructions=b""),
    x_min: 0,
    y_min: 0,
    x_max: 0,
    y_max: 0,
    advance: 1000,
    lsb: 0,
  })
  let (xs, ys) = collect_glyph_points(glyphs, 2, [], Ref(0), 1000)
  assert_eq(xs.length(), 9)
  assert_eq((xs[7], ys[7]), (xs[5], ys[5]))
}
