# Embed the instancer

The library takes bytes and returns bytes; callers choose their own file,
browser, build-cache or document integration. All omitted axes select defaults,
so this function produces a fully static font at the requested weight.

```mbt check
///|
fn static_weight(
  source : Bytes,
  weight : Double,
) -> Bytes raise @fontpin.FontError {
  let font = @fontpin.Font::parse(source)
  let instance = font.instantiate({ "wght": weight })
  instance.to_bytes()
}

///|
test "embedding callers can distinguish an unsupported font flavor" {
  let unsupported = try {
    ignore(static_weight(b"OTTO", 650.0))
    false
  } catch {
    @fontpin.Unsupported(_) => true
    _ => false
  }
  assert_true(unsupported)
}
```

Use `font.axes()` before choosing coordinates when processing an unknown family.
Catch `Invalid`, `Unsupported` and `Limit` to present the appropriate diagnostic;
do not publish an output when conversion fails. The real-font command-line
workflow in the repository README supplies a complete file-to-file example.

The font designer's presets can be selected with `font.named_instances()` and
`font.instantiate_named(index)`. The catalog always places the default design
position at index zero. Returned coordinates are detached from the source font.

```mbt check
///|
fn designer_style(
  source : Bytes,
  index : Int32,
) -> Bytes raise @fontpin.FontError {
  @fontpin.Font::parse(source).instantiate_named(index).to_bytes()
}

///|
test "named selection propagates typed source errors" {
  assert_true(
    try {
      ignore(designer_style(b"OTTO", 0))
      false
    } catch {
      @fontpin.Unsupported(_) => true
      _ => false
    },
  )
}
```

Plans can be validated and stored without opening a font or touching files.
The same canonical plan is usable by the portable API and the batch CLI.

```mbt check
///|
test "a portable asset plan round trips before conversion" {
  let plan = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"body.ttf\",\"coordinates\":{\"wght\":400}}]}",
  )
  assert_eq(plan.filenames(), ["body.ttf"])
  let canonical = plan.to_json().stringify()
  assert_eq(
    @fontpin.BatchPlan::parse(canonical).to_json().stringify(),
    canonical,
  )
}
```

Call `font.instantiate_batch(plan)` to get complete `BatchArtifact` values.
Each artifact has a `filename` and an `instance`; publish the returned list only
after the call succeeds. Coordinate and preset errors identify the output file.

`instance.layout_report()` returns detached layout evidence; `report_json()`
also includes it under `layout`. Counts cover VariationIndex references visited
in the full layout pass, including repeated references and zero deltas. They do
not describe rendered text. Conditional record indices are zero-based or null.

```mbt check
///|
fn artifact_with_layout_audit(
  source : Bytes,
  coordinates : Map[String, Double],
) -> (Bytes, Json) raise @fontpin.FontError {
  let instance = @fontpin.Font::parse(source).instantiate(coordinates)
  (instance.to_bytes(), instance.layout_report())
}

///|
test "an embedding caller receives static font bytes with versioned layout evidence" {
  let (bytes, audit) = artifact_with_layout_audit(layout_test_font_bytes(), {
    "wght": 650.0,
    "wdth": 87.5,
  })
  match @fontpin.inspect_font(bytes) {
    { "axes": Array(axes), .. } => assert_true(axes.is_empty())
    _ => fail("output failed static reload")
  }
  match audit {
    { "version": Number(1, ..), "rewritten_tables": Array(tables), .. } =>
      assert_eq(tables.length(), 3)
    _ => fail("layout evidence is missing")
  }
}
```
