///|
test "batch plans round trip canonically and detach filename and JSON snapshots" {
  let source = "{\"outputs\":[{\"preset\":2,\"file\":\"z.ttf\"},{\"coordinates\":{\"wght\":650,\"wdth\":87.5},\"file\":\"a.ttf\"}],\"version\":1}"
  let plan = @fontpin.BatchPlan::parse(source)
  let canonical = plan.to_json().stringify()
  assert_eq(
    @fontpin.BatchPlan::parse(canonical).to_json().stringify(),
    canonical,
  )
  let reordered = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":{\"wdth\":87.5,\"wght\":650}},{\"file\":\"z.ttf\",\"preset\":2}]}",
  )
  assert_eq(reordered.to_json().stringify(), canonical)
  let files = plan.filenames()
  assert_eq(files, ["a.ttf", "z.ttf"])
  files.clear()
  assert_eq(plan.filenames(), ["a.ttf", "z.ttf"])
  if plan.to_json() is Object(fields) {
    fields.clear()
  }
  assert_eq(plan.to_json().stringify(), canonical)
}

///|
test "batch schema refuses unknown fields, ambiguous selections and malformed JSON" {
  for
    source in [
      "[]", "{", "{\"version\":1}", "{\"version\":1,\"outputs\":[],\"extra\":0}",
      "{\"version\":1,\"outputs\":[null]}", "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\"}]}",
      "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"preset\":0,\"coordinates\":{}}]}",
      "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"preset\":0,\"unused\":null}]}",
      "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":[]}]}",
    ] {
    assert_true(
      try {
        ignore(@fontpin.BatchPlan::parse(source))
        false
      } catch {
        @fontpin.Invalid(_) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(@fontpin.BatchPlan::parse("{\"version\":2,\"outputs\":[]}"))
      false
    } catch {
      @fontpin.Unsupported(_) => true
      _ => false
    },
  )
}

///|
test "batch duplicate JSON keys are rejected after unescaping at every depth" {
  for
    source in [
      "{\"version\":2,\"version\":1,\"outputs\":[]}", "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"file\":\"b.ttf\",\"preset\":0}]}",
      "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"\\u0066ile\":\"b.ttf\",\"preset\":0}]}",
      "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":{\"wght\":100,\"\\u0077ght\":400}}]}",
    ] {
    assert_true(
      try {
        ignore(@fontpin.BatchPlan::parse(source))
        false
      } catch {
        @fontpin.Invalid(detail) => detail.contains("duplicate batch JSON key")
        _ => false
      },
    )
  }
  // Repeated keys in different output objects are independent scopes.
  let valid = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"preset\":0},{\"file\":\"b.ttf\",\"preset\":0}]}",
  )
  assert_eq(valid.filenames(), ["a.ttf", "b.ttf"])
}

///|
test "batch filenames are portable and cannot escape their output directory" {
  for
    filename in [
      "../a.ttf", "/a.ttf", "a/b.ttf", "C:\\a.ttf", "a\\b.ttf", "a..ttf", "a .ttf",
      "字.ttf", "a.TTF", "CON.ttf", "nul.ttf", "COM1.ttf", "lpt9.ttf", ".ttf",
    ] {
    let text : Json = {
      "version": 1,
      "outputs": [{ "file": Json(filename), "preset": 0 }],
    }
    assert_true(
      try {
        ignore(@fontpin.BatchPlan::parse(text.stringify()))
        false
      } catch {
        @fontpin.Invalid(_) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(
        @fontpin.BatchPlan::parse(
          "{\"version\":1,\"outputs\":[{\"file\":\"A.ttf\",\"preset\":0},{\"file\":\"a.ttf\",\"preset\":1}]}",
        ),
      )
      false
    } catch {
      @fontpin.Invalid(detail) => detail.contains("ignoring ASCII case")
      _ => false
    },
  )
  let stem = StringBuilder()
  for _ in 0..<96 {
    stem.write_char('a')
  }
  let valid : Json = {
    "version": 1,
    "outputs": [{ "file": Json(stem.to_string() + ".ttf"), "preset": 0 }],
  }
  assert_eq(
    @fontpin.BatchPlan::parse(valid.stringify()).filenames().length(),
    1,
  )
  stem.write_char('a')
  let invalid : Json = {
    "version": 1,
    "outputs": [{ "file": Json(stem.to_string() + ".ttf"), "preset": 0 }],
  }
  assert_true(
    try {
      ignore(@fontpin.BatchPlan::parse(invalid.stringify()))
      false
    } catch {
      @fontpin.Invalid(_) => true
      _ => false
    },
  )
}

///|
test "batch manifest size, count, selectors and coordinate types are bounded" {
  for selector in ["-1", "1.5", "1024", "1e9999", "\"0\""] {
    assert_true(
      try {
        ignore(
          @fontpin.BatchPlan::parse(
            "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"preset\":" +
            selector +
            "}]}",
          ),
        )
        false
      } catch {
        @fontpin.Invalid(_) => true
        _ => false
      },
    )
  }
  for
    coordinates in [
      "{\"wght\":null}", "{\"wght\":1e9999}", "{\"x\":1}", "{\"字体大小\":1}",
    ] {
    assert_true(
      try {
        ignore(
          @fontpin.BatchPlan::parse(
            "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":" +
            coordinates +
            "}]}",
          ),
        )
        false
      } catch {
        @fontpin.Invalid(_) => true
        _ => false
      },
    )
  }
  let rows : Array[Json] = []
  for i in 0..<16 {
    rows.push({ "file": Json("font" + i.to_string() + ".ttf"), "preset": 0 })
  }
  let valid : Json = { "version": 1, "outputs": Json(rows) }
  assert_eq(
    @fontpin.BatchPlan::parse(valid.stringify()).filenames().length(),
    16,
  )
  rows.push({ "file": "extra.ttf", "preset": 0 })
  let invalid : Json = { "version": 1, "outputs": Json(rows) }
  assert_true(
    try {
      ignore(@fontpin.BatchPlan::parse(invalid.stringify()))
      false
    } catch {
      @fontpin.Limit(_) => true
      _ => false
    },
  )
  let small = "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":{}}]}"
  let padded = StringBuilder()
  for _ in 0..<(65536 - small.length()) {
    padded.write_char(' ')
  }
  padded.write_string(small)
  ignore(@fontpin.BatchPlan::parse(padded.to_string()))
  padded.write_char(' ')
  assert_true(
    try {
      ignore(@fontpin.BatchPlan::parse(padded.to_string()))
      false
    } catch {
      @fontpin.Limit(_) => true
      _ => false
    },
  )
}

///|
test "batch instancing matches independent single conversions and preserves the source" {
  let font = @fontpin.Font::parse(named_test_font_bytes())
  let plan = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"z.ttf\",\"preset\":2},{\"file\":\"a.ttf\",\"coordinates\":{\"wght\":650,\"wdth\":87.5}}]}",
  )
  let artifacts = font.instantiate_batch(plan)
  assert_eq(artifacts.map(artifact => artifact.filename), ["a.ttf", "z.ttf"])
  assert_eq(
    artifacts[0].instance.to_bytes(),
    font.instantiate_named(1).to_bytes(),
  )
  assert_eq(
    artifacts[1].instance.to_bytes(),
    font.instantiate_named(2).to_bytes(),
  )
  assert_eq(
    font.instantiate_batch(plan)[0].instance.to_bytes(),
    artifacts[0].instance.to_bytes(),
  )
  for artifact in artifacts {
    match @fontpin.inspect_font(artifact.instance.to_bytes()) {
      { "axes": Array(axes), .. } => assert_true(axes.is_empty())
      _ => fail("batch output failed static reload")
    }
  }
  let total = artifacts.fold(init=0, (sum, artifact) => {
    sum + artifact.instance.to_bytes().length()
  })
  assert_true(
    try {
      ignore(font.instantiate_batch(plan, max_total_bytes=total - 1))
      false
    } catch {
      @fontpin.Limit(detail) => detail.contains("total-byte")
      _ => false
    },
  )
  assert_eq(
    font.instantiate_batch(plan, max_total_bytes=total)[1].instance.to_bytes(),
    artifacts[1].instance.to_bytes(),
  )
}

///|
test "batch validates every position before spending conversion work and recovers" {
  let font = @fontpin.Font::parse(named_test_font_bytes())
  let invalid = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":{}},{\"file\":\"z.ttf\",\"coordinates\":{\"zzzz\":1}}]}",
  )
  assert_true(
    try {
      ignore(font.instantiate_batch(invalid, work_limit=1))
      false
    } catch {
      @fontpin.Invalid(detail) =>
        detail.contains("z.ttf") && detail.contains("unknown axis")
      _ => false
    },
  )
  let missing = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"missing.ttf\",\"preset\":3}]}",
  )
  assert_true(
    try {
      ignore(font.instantiate_batch(missing))
      false
    } catch {
      @fontpin.Invalid(detail) => detail.contains("missing.ttf")
      _ => false
    },
  )
  let valid = @fontpin.BatchPlan::parse(
    "{\"version\":1,\"outputs\":[{\"file\":\"a.ttf\",\"coordinates\":{}}]}",
  )
  for budget in [0, 134217729] {
    assert_true(
      try {
        ignore(font.instantiate_batch(valid, max_total_bytes=budget))
        false
      } catch {
        @fontpin.Limit(_) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(font.instantiate_batch(valid, work_limit=1))
      false
    } catch {
      @fontpin.Limit(detail) => detail.contains("a.ttf")
      _ => false
    },
  )
  assert_eq(
    font.instantiate_batch(valid)[0].instance.to_bytes(),
    font.instantiate({}).to_bytes(),
  )
}
