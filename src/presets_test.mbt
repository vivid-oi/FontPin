///|
test "public named catalog exposes stable indices and detached positions" {
  let font = @fontpin.Font::parse(named_test_font_bytes())
  let entries = font.named_instances()
  assert_eq(entries.map(entry => entry.label), [
    "Regular", "Narrow Medium", "Wide Bold",
  ])
  assert_eq(entries.map(entry => entry.source_index), [
    Some(1),
    Some(0),
    Some(2),
  ])
  assert_eq(entries.map(entry => entry.index), [0, 1, 2])
  assert_eq(entries[1].coordinates["wght"], 650.0)
  assert_eq(entries[1].coordinates["wdth"], 87.5)
  assert_eq(entries[1].postscript_name_id, Some(261))
  match entries[1].to_json() {
    { "label": String("Narrow Medium"), "source_index": Number(0, ..), .. } =>
      ()
    _ => fail("catalog entry does not serialize its public metadata")
  }
  entries[1].coordinates["wght"] = 100.0
  assert_eq(font.named_instances()[1].coordinates["wght"], 650.0)
}

///|
test "public named conversion equals coordinate conversion and reloads as static" {
  let source = named_test_font_bytes()
  let font = @fontpin.Font::parse(source)
  for entry in font.named_instances() {
    let output = font.instantiate_named(entry.index).to_bytes()
    assert_eq(output, font.instantiate(entry.coordinates).to_bytes())
    assert_eq(output, font.instantiate_named(entry.index).to_bytes())
    match @fontpin.inspect_font(output) {
      { "axes": Array(axes), .. } => assert_true(axes.is_empty())
      _ => fail("static font inspection failed")
    }
  }
  assert_eq(source, named_test_font_bytes())
}

///|
test "public named conversion rejects invalid selectors and propagates resource limits" {
  let font = @fontpin.Font::parse(named_test_font_bytes())
  for index in [-1, 3, 2147483647] {
    assert_true(
      try {
        ignore(font.instantiate_named(index))
        false
      } catch {
        @fontpin.Invalid(detail) => detail.contains("list presets")
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(font.instantiate_named(1, work_limit=1))
      false
    } catch {
      @fontpin.Limit(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(font.instantiate_named(1, max_bytes=1024))
      false
    } catch {
      @fontpin.Limit(_) => true
      _ => false
    },
  )
  assert_eq(
    font.instantiate_named(1).to_bytes(),
    font.instantiate({ "wght": 650.0, "wdth": 87.5 }).to_bytes(),
  )
}
