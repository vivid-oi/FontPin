///|
fn preset_test_tables() -> Map[String, Bytes] raise FontError {
  let tables = api_fixture_tables()
  let fvar = byte_array(tables["fvar"])
  set_u16(fvar, 12, 2)
  set_u16(fvar, 14, 10)
  for (id, weight, ps) in [(256, 700, 65535), (2, 400, 6)] {
    push_u16(fvar, id)
    push_u16(fvar, 0)
    push_u32(fvar, weight.reinterpret_as_uint() << 16)
    push_u16(fvar, ps)
  }
  tables["fvar"] = Bytes::from_array(fvar[:])
  let original = tables["name"]
  let count = read_u16(original, 2)
  let base = read_u16(original, 4)
  let name = byte_array(original[0:base].to_owned())
  set_u16(name, 2, count + 1)
  set_u16(name, 4, base + 12)
  for value in [3, 1, 0x409, 256, 8, original.length() - base] {
    push_u16(name, value)
  }
  for byte in original[base:] {
    name.push(byte)
  }
  for byte in b"\x00B\x00o\x00l\x00d" {
    name.push(byte)
  }
  tables["name"] = Bytes::from_array(name[:])
  tables
}

///|
test "named catalog orders the default first and detaches mutable coordinates" {
  let font = Font::parse(build_sfnt(preset_test_tables(), 100000))
  let entries = font.named_instances()
  assert_eq(entries.length(), 2)
  assert_eq(
    (entries[0].index, entries[0].source_index, entries[0].label),
    (0, Some(1), "Regular"),
  )
  assert_eq(
    (entries[1].index, entries[1].source_index, entries[1].label),
    (1, Some(0), "Bold"),
  )
  assert_eq(entries[0].postscript_name_id, Some(6))
  assert_eq(entries[1].postscript_name_id, None)
  let expected = font.instantiate({ "wght": 700.0 }).to_bytes()
  assert_eq(font.instantiate_named(1).to_bytes(), expected)
  entries[1].coordinates["wght"] = 100.0
  entries.clear()
  assert_eq(font.named_instances()[1].coordinates["wght"], 700.0)
  assert_eq(font.instantiate_named(1).to_bytes(), expected)
  for index in [-1, 2, 2147483647] {
    assert_true(
      try {
        ignore(font.instantiate_named(index))
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
  assert_eq(font.instantiate_named(1).to_bytes(), expected)
}

///|
test "named catalog synthesizes a default for fonts without a matching record" {
  let no_records = Font::parse(build_sfnt(api_fixture_tables(), 100000))
  let entries = no_records.named_instances()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].source_index, None)
  assert_eq(entries[0].name_id, 17)
  assert_eq(entries[0].coordinates["wght"], 400.0)
  assert_eq(
    no_records.instantiate_named(0).to_bytes(),
    no_records.instantiate({}).to_bytes(),
  )
  let tables = preset_test_tables()
  let fvar = byte_array(tables["fvar"])
  set_u16(fvar, 12, 1)
  tables["fvar"] = Bytes::from_array(fvar[0:46])
  let entries = Font::parse(build_sfnt(tables, 100000)).named_instances()
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].source_index, None)
  assert_eq(entries[1].source_index, Some(0))
}

///|
test "named catalog validates flags, name references and design positions" {
  let source = preset_test_tables()
  for
    (offset, value) in [(36, 1), (38, 1), (44, 5), (44, 300), (36, 2), (44, 6)] {
    let tables = source.copy()
    let fvar = byte_array(tables["fvar"])
    set_u16(fvar, offset, value)
    tables["fvar"] = Bytes::from_array(fvar[:])
    let font = Font::parse(build_sfnt(tables, 100000))
    assert_true(
      try {
        ignore(font.named_instances())
        false
      } catch {
        Invalid(_) | Unsupported(_) => true
        _ => false
      },
    )
    // Selecting explicit coordinates remains available for unrelated bad presets.
    ignore(font.instantiate({ "wght": 400.0 }))
  }
  let tables = source.copy()
  let fvar = byte_array(tables["fvar"])
  set_u32(fvar, 40, 701U << 16)
  tables["fvar"] = Bytes::from_array(fvar[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).named_instances())
      false
    } catch {
      Invalid(detail) => detail.contains("range")
      _ => false
    },
  )
}

///|
test "catalog labels decode Unicode pairs and reject malformed or unbounded labels" {
  let tables = preset_test_tables()
  let name = byte_array(tables["name"])
  let count = read_u16(tables["name"], 2)
  let p = 6 + (count - 1) * 12
  set_u16(name, p + 8, 6)
  set_u16(name, p + 10, tables["name"].length() - read_u16(tables["name"], 4))
  for byte in b"\x5b\x57\xd8\x3d\xde\x00" {
    name.push(byte)
  }
  tables["name"] = Bytes::from_array(name[:])
  assert_eq(
    Font::parse(build_sfnt(tables, 100000)).named_instances()[1].label,
    "字😀",
  )
  let malformed = byte_array(tables["name"])
  set_u16(malformed, p + 8, 3)
  tables["name"] = Bytes::from_array(malformed[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).named_instances())
      false
    } catch {
      Invalid(_) => true
      _ => false
    },
  )
  set_u16(malformed, p + 2, 4)
  set_u16(malformed, p + 8, 6)
  tables["name"] = Bytes::from_array(malformed[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).named_instances())
      false
    } catch {
      Unsupported(_) => true
      _ => false
    },
  )
  let oversized = byte_array(Bytes::from_array(name[:]))
  set_u16(oversized, p + 8, 4098)
  set_u16(oversized, p + 10, oversized.length() - read_u16(tables["name"], 4))
  for _ in 0..<4098 {
    oversized.push(0)
  }
  tables["name"] = Bytes::from_array(oversized[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).named_instances())
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  let many = api_fixture_tables()
  let fvar = byte_array(many["fvar"])
  set_u16(fvar, 12, 1024)
  for _ in 0..<1024 {
    push_u16(fvar, 256)
    push_u16(fvar, 0)
    push_u32(fvar, 400U << 16)
  }
  many["fvar"] = Bytes::from_array(fvar[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(many, 100000)).named_instances())
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
}

///|
test "named labels accept format-1 language references and validate their range" {
  let tables = preset_test_tables()
  let original = tables["name"]
  let base = read_u16(original, 4)
  let count = read_u16(original, 2)
  let name = byte_array(original[0:base].to_owned())
  set_u16(name, 0, 1)
  set_u16(name, 4, base + 6)
  push_u16(name, 1)
  push_u16(name, 4)
  push_u16(name, original.length() - base)
  for i in 0..<count {
    set_u16(name, 10 + i * 12, 0x8000)
  }
  for byte in original[base:] {
    name.push(byte)
  }
  for byte in b"\x00e\x00n" {
    name.push(byte)
  }
  tables["name"] = Bytes::from_array(name[:])
  assert_eq(
    Font::parse(build_sfnt(tables, 100000)).named_instances()[1].label,
    "Bold",
  )
  set_u16(name, 10, 0x8001)
  tables["name"] = Bytes::from_array(name[:])
  assert_true(
    try {
      ignore(Font::parse(build_sfnt(tables, 100000)).named_instances())
      false
    } catch {
      Invalid(detail) => detail.contains("language reference")
      _ => false
    },
  )
}
