///|
fn name_test_format1() -> Bytes raise FontError {
  let original = api_fixture_tables()["name"]
  let n = read_u16(original, 2)
  let base = read_u16(original, 4)
  let out = byte_array(original[0:base].to_owned())
  set_u16(out, 0, 1)
  set_u16(out, 4, base + 10)
  let strings = byte_array(original[base:].to_owned())
  push_u16(out, 2)
  for language in [b"\x00e\x00n", b"\x00z\x00h\x00-\x00H\x00a\x00n\x00t"] {
    push_u16(out, language.length())
    push_u16(out, strings.length())
    for byte in language {
      strings.push(byte)
    }
  }
  // Unreferenced storage is retained too; it must not be silently erased.
  strings.push(0xA5)
  for i in 0..<n {
    set_u16(out, 10 + i * 12, 0x8000 + i % 2)
  }
  for byte in strings {
    out.push(byte)
  }
  Bytes::from_array(out[:])
}

///|
test "format-1 instancing preserves language associations and complete source storage" {
  let tables = api_fixture_tables()
  let original = name_test_format1()
  tables["name"] = original
  let source = build_sfnt(tables, 100000)
  let font = Font::parse(source)
  let output = font.instantiate({ "wght": 700.0 }).to_bytes()
  let result = parse_sfnt(output, 100000)["name"]
  let base = read_u16(original, 4)
  let n = read_u16(original, 2)
  assert_eq(read_u16(result, 0), 1)
  assert_eq(read_u16(result, 4), base)
  assert_eq(result[6 + n * 12:base], original[6 + n * 12:base])
  assert_eq(result[base:original.length()], original[base:])
  for i in 0..<n {
    assert_eq(read_u16(result, 10 + i * 12), 0x8000 + i % 2)
  }
  for id in [0, 1, 13, 16] {
    assert_eq(test_name(result, id), test_name(original, id))
  }
  assert_eq(test_name(result, 2), b"\x00w\x00g\x00h\x00t\x007\x000\x000")
  assert_eq(font.instantiate({ "wght": 700.0 }).to_bytes(), output)
  assert_eq(parse_sfnt(source, 100000)["name"], original)
  assert_eq(build_sfnt(parse_sfnt(output, 100000), 100000), output)
}

///|
test "format-1 malformed language records, references and offsets fail explicitly" {
  let original = name_test_format1()
  let n = read_u16(original, 2)
  let malformed : Array[Bytes] = []
  for
    (offset, value) in [
      (10, 0x8002),
      (6 + n * 12, 65535),
      (8 + n * 12, 3),
      (10 + n * 12, 65535),
      (4, 6),
    ] {
    let data = byte_array(original)
    set_u16(data, offset, value)
    malformed.push(Bytes::from_array(data[:]))
  }
  for name in malformed {
    let tables = api_fixture_tables()
    tables["name"] = name
    assert_true(
      try {
        update_instance_names(tables, { "wght": 700.0 })
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
    assert_eq(tables["name"], name)
  }
  for value in [b"", b"en-", b"en--US", b"en_Us", b"123", b"abcdefghi", b"\xff"] {
    assert_true(
      try {
        validate_language_tag(value, 1)
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
  for value in [b"en", b"zh-Hant", b"gsw-LI", b"x-private", b"i-klingon"] {
    validate_language_tag(value, 1)
  }
}

///|
test "ltag remains byte-exact and Unicode language IDs are checked" {
  let original : Bytes = b"\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x10\x00\x06gsw-LI"
  let tables = api_fixture_tables()
  tables["ltag"] = original
  let name = byte_array(tables["name"])
  for i in 0..<read_u16(tables["name"], 2) {
    set_u16(name, 6 + i * 12, 0)
    set_u16(name, 10 + i * 12, 0)
  }
  tables["name"] = Bytes::from_array(name[:])
  let source = build_sfnt(tables, 100000)
  let result = Font::parse(source).instantiate({ "wght": 700.0 }).to_bytes()
  assert_eq(parse_sfnt(result, 100000)["ltag"], original)
  for length in 0..<original.length() {
    let bad = tables.copy()
    bad["ltag"] = original[0:length].to_owned()
    assert_true(
      try {
        ignore(validate_ltag(bad))
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
  set_u16(name, 10, 1)
  tables["name"] = Bytes::from_array(name[:])
  assert_true(
    try {
      update_instance_names(tables, { "wght": 700.0 })
      false
    } catch {
      Invalid(_) => true
      _ => false
    },
  )
  assert_eq(
    Font::parse(source).instantiate({ "wght": 700.0 }).to_bytes(),
    result,
  )
}

///|
test "localized full names retain valid surrogate pairs and reject lossy encodings" {
  let tables = api_fixture_tables()
  let source = tables["name"]
  let n = read_u16(source, 2)
  let name = byte_array(source)
  let mut full = 0
  for i in 0..<n {
    if read_u16(source, 12 + i * 12) == 4 {
      full = 6 + i * 12
    }
  }
  set_u16(name, full + 8, 6)
  set_u16(name, full + 10, source.length() - read_u16(source, 4))
  for byte in b"\x5b\x57\xd8\x3d\xde\x00" {
    name.push(byte)
  }
  tables["name"] = Bytes::from_array(name[:])
  update_instance_names(tables, { "wght": 700.0 })
  let prefix = test_name(tables["name"], 4)
  assert_eq(prefix[0:6], b"\x5b\x57\xd8\x3d\xde\x00"[:])
  for bytes in [b"\x00", b"\xd8\x00", b"\xdc\x00", b"\xd8\x00\x00A"] {
    assert_true(
      try {
        validate_name_utf16(bytes)
        false
      } catch {
        Invalid(_) => true
        _ => false
      },
    )
  }
  let bad = byte_array(source)
  set_u16(bad, full + 2, 4)
  tables["name"] = Bytes::from_array(bad[:])
  assert_true(
    try {
      update_instance_names(tables, { "wght": 700.0 })
      false
    } catch {
      Unsupported(detail) => detail.contains("encoding")
      _ => false
    },
  )
}

///|
test "Unicode language-neutral format-0 names remain valid without ltag" {
  let tables = api_fixture_tables()
  let name = byte_array(tables["name"])
  for i in 0..<read_u16(tables["name"], 2) {
    set_u16(name, 6 + i * 12, 0)
    set_u16(name, 10 + i * 12, 0)
  }
  tables["name"] = Bytes::from_array(name[:])
  ignore(Font::parse(build_sfnt(tables, 100000)).instantiate({}))
}
