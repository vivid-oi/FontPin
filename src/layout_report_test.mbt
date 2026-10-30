///|
test "public layout audit describes resolved branches, references and rewritten tables" {
  let font = @fontpin.Font::parse(layout_test_font_bytes())
  let instance = font.instantiate({ "wght": 650.0, "wdth": 87.5 })
  let expected : Json = {
    "version": 1,
    "variation_indices": { "GDEF": 1, "GPOS": 8 },
    "gpos_lookup_types": [1, 1, 2, 2, 7, 7, 7, 8, 8, 8],
    "feature_variations": {
      "GSUB": { "present": true, "record": 0 },
      "GPOS": { "present": true, "record": 0 },
    },
    "rewritten_tables": ["GDEF", "GPOS", "GSUB"],
  }
  assert_eq(instance.layout_report(), expected)
  match instance.report_json() {
    { "layout": value, .. } => assert_eq(value, expected)
    _ => fail("conversion summary omitted layout evidence")
  }
  for
    (coordinates, selected) in [
      ({ "wght": 100.0 }, None),
      ({ "wght": 400.0 }, Some(1)),
      ({ "wght": 900.0, "wdth": 125.0 }, Some(1)),
    ] {
    match font.instantiate(coordinates).layout_report() {
      {
        "feature_variations": {
          "GSUB": { "present": True, "record": record, .. },
          ..
        },
        ..
      } =>
        assert_eq(
          record,
          match selected {
            Some(index) => Json(index)
            None => null
          },
        )
      _ => fail("conditional report omitted branch metadata")
    }
  }
  assert_eq(
    instance.to_bytes(),
    font.instantiate({ "wght": 650.0, "wdth": 87.5 }).to_bytes(),
  )
  match @fontpin.inspect_font(instance.to_bytes()) {
    { "axes": Array(axes), .. } => assert_true(axes.is_empty())
    _ => fail("static layout output failed to reload")
  }
}

///|
test "audit values are detached and prior results survive failed conversion" {
  let font = @fontpin.Font::parse(layout_test_font_bytes())
  let instance = font.instantiate({})
  let expected = instance.layout_report().stringify()
  match instance.layout_report() {
    Object(fields) => {
      fields["version"] = 999
      match fields.get("gpos_lookup_types") {
        Some(Array(types)) => types.clear()
        _ => fail("missing types")
      }
      match fields.get("feature_variations") {
        Some(Object(features)) => features.clear()
        _ => fail("missing features")
      }
    }
    _ => fail("report is not an object")
  }
  assert_true(
    try {
      ignore(font.instantiate({ "wght": 901.0 }))
      false
    } catch {
      @fontpin.Invalid(_) => true
      _ => false
    },
  )
  assert_eq(instance.layout_report().stringify(), expected)
  assert_eq(font.instantiate({}).layout_report().stringify(), expected)
  assert_eq(
    @fontpin.Font::parse(named_test_font_bytes())
    .instantiate({})
    .layout_report(),
    {
      "version": 1,
      "variation_indices": { "GDEF": 0, "GPOS": 0 },
      "gpos_lookup_types": [],
      "feature_variations": {
        "GSUB": { "present": false, "record": null },
        "GPOS": { "present": false, "record": null },
      },
      "rewritten_tables": [],
    },
  )
}
