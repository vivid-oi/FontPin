///|
fn api_fixture_tables() -> Map[String, Bytes] raise FontError {
  let tables = glyph_fixture_tables()
  let head = byte_array(tables["head"])
  set_u32(head, 0, 0x00010000U)
  set_u32(head, 12, 0x5F0F3CF5U)
  set_u16(head, 18, 1000)
  tables["head"] = Bytes::from_array(head[:])
  let maxp = byte_array(tables["maxp"])
  set_u32(maxp, 0, 0x00010000U)
  tables["maxp"] = Bytes::from_array(maxp[:])
  let os2 = Array::make(96, (0 : Byte))
  set_u16(os2, 0, 4)
  set_u16(os2, 4, 400)
  set_u16(os2, 6, 5)
  set_u16(os2, 62, 64)
  tables["OS/2"] = Bytes::from_array(os2[:])
  let post = Array::make(32, (0 : Byte))
  set_u32(post, 0, 0x00030000U)
  tables["post"] = Bytes::from_array(post[:])
  tables["cmap"] = b"\x00\x00\x00\x01\x00\x03\x00\x0a\x00\x00\x00\x0c\x00\x0c\x00\x00\x00\x00\x00\x1c\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x20\x00\x00\x00\x20\x00\x00\x00\x00"
  let fvar = Array::make(36, (0 : Byte))
  set_u16(fvar, 0, 1)
  set_u16(fvar, 4, 16)
  set_u16(fvar, 6, 2)
  set_u16(fvar, 8, 1)
  set_u16(fvar, 10, 20)
  set_u16(fvar, 14, 8)
  for i, byte in b"wght" {
    fvar[16 + i] = byte
  }
  set_u32(fvar, 20, 100U << 16)
  set_u32(fvar, 24, 400U << 16)
  set_u32(fvar, 28, 700U << 16)
  set_u16(fvar, 34, 256)
  tables["fvar"] = Bytes::from_array(fvar[:])
  let entries = [
    (0, "Copyright fixture"),
    (1, "SampleFamily"),
    (2, "Regular"),
    (3, "SampleFamily;1.0"),
    (4, "SampleFamily Regular"),
    (6, "SampleFamily-Regular"),
    (13, "Fixture license"),
    (16, "SampleFamily"),
    (17, "Regular"),
  ]
  let name = Array::make(6 + entries.length() * 12, (0 : Byte))
  let strings : Array[Byte] = []
  set_u16(name, 2, entries.length())
  set_u16(name, 4, name.length())
  for i, (id, text) in entries {
    let p = 6 + i * 12
    set_u16(name, p, 3)
    set_u16(name, p + 2, 1)
    set_u16(name, p + 4, 0x409)
    set_u16(name, p + 6, id)
    set_u16(name, p + 8, text.length() * 2)
    set_u16(name, p + 10, strings.length())
    for ch in text {
      push_u16(strings, ch.to_int())
    }
  }
  for byte in strings {
    name.push(byte)
  }
  tables["name"] = Bytes::from_array(name[:])
  tables
}

///|
fn test_name(table : Bytes, id : Int32) -> Bytes raise FontError {
  for i in 0..<read_u16(table, 2) {
    let p = 6 + i * 12
    if read_u16(table, p + 6) == id {
      let start = read_u16(table, 4) + read_u16(table, p + 10)
      return table[start:start + read_u16(table, p + 8)].to_owned()
    }
  }
  raise Invalid("fixture name missing")
}

///|
test "public workflow emits deterministic static font and preserves metadata" {
  let source = build_sfnt(api_fixture_tables(), 100000)
  let font = Font::parse(source)
  assert_eq(font.axes().length(), 1)
  let external_axes = font.axes()
  external_axes.clear()
  assert_eq(font.axes().length(), 1)
  let output = font.instantiate({ "wght": 700.0 }).to_bytes()
  assert_eq(output, font.instantiate({ "wght": 700.0 }).to_bytes())
  let before = parse_sfnt(source, 100000)
  let after = parse_sfnt(output, 100000)
  for tag in ["fvar", "avar", "gvar", "HVAR"] {
    assert_false(after.contains(tag))
  }
  for tag in ["cmap", "post", "maxp"] {
    assert_eq(before[tag], after[tag])
  }
  for id in [0, 1, 13, 16] {
    assert_eq(test_name(before["name"], id), test_name(after["name"], id))
  }
  assert_true(
    test_name(after["name"], 6).length() > test_name(before["name"], 6).length(),
  )
  assert_eq(read_u16(after["OS/2"], 4), 700)
  assert_eq(read_u16(after["OS/2"], 62) & 32, 32)
  assert_eq(read_u16(after["head"], 44) & 1, 1)
  assert_eq(build_sfnt(after, 100000), output)
  ignore(inspect_font(output))
  assert_eq(build_sfnt(before, 100000), source)
}

///|
test "axis boundaries, invalid coordinates, resource limits and recovery" {
  let font = Font::parse(build_sfnt(api_fixture_tables(), 100000))
  for weight in [100.0, 400.0, 700.0] {
    ignore(font.instantiate({ "wght": weight }))
  }
  assert_eq(
    font.instantiate({}).to_bytes(),
    font.instantiate({ "wght": 400.0 }).to_bytes(),
  )
  for
    coords in [
      { "wght": 99.0 },
      { "wght": 701.0 },
      { "fake": 400.0 },
      { "wght": 0x7ff0000000000000UL.reinterpret_as_double() },
      { "wght": 0x7ff8000000000000UL.reinterpret_as_double() },
    ] {
    let rejected = try {
      ignore(font.instantiate(coords))
      false
    } catch {
      Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(font.instantiate({}, work_limit=1))
    false
  } catch {
    Limit(_) => true
    _ => false
  }
  assert_true(rejected)
  ignore(font.instantiate({ "wght": 650.0 }))
}

///|
test "unknown tables and corrupt sfnt never yield a partial conversion" {
  let tables = api_fixture_tables()
  tables["TEST"] = b"cannot discard this"
  let font = Font::parse(build_sfnt(tables, 100000))
  let rejected = try {
    ignore(font.instantiate({}))
    false
  } catch {
    Unsupported(detail) => detail.contains("TEST")
    _ => false
  }
  assert_true(rejected)
  let data = byte_array(build_sfnt(api_fixture_tables(), 100000))
  data[data.length() - 1] = data[data.length() - 1] ^ 1
  let rejected = try {
    ignore(Font::parse(Bytes::from_array(data[:])))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  for size in 0..<12 {
    let rejected = try {
      ignore(Font::parse(Bytes::from_array(data[:size])))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "checksummed unreferenced sfnt bytes are refused rather than discarded" {
  let source = build_sfnt(api_fixture_tables(), 100000)
  let bytes = byte_array(source)
  for byte in b"unclaimed" {
    bytes.push(byte)
  }
  let mut head_at = 0
  for i in 0..<read_u16(source, 4) {
    if read_tag(source, 12 + i * 16) == "head" {
      head_at = read_u32(source, 20 + i * 16)
    }
  }
  set_u32(bytes, head_at + 8, 0U)
  set_u32(
    bytes,
    head_at + 8,
    0xB1B0AFBAU - checksum(Bytes::from_array(bytes[:])),
  )
  assert_eq(checksum(Bytes::from_array(bytes[:])), 0xB1B0AFBAU)
  let rejected = try {
    ignore(Font::parse(Bytes::from_array(bytes[:])))
    false
  } catch {
    Invalid(detail) => detail.contains("after declared")
    _ => false
  }
  assert_true(rejected)
  ignore(Font::parse(source))
}

///|
test "full MVAR workflow freezes global metrics without mutating the source" {
  let tables = api_fixture_tables()
  let os2 = byte_array(tables["OS/2"])
  set_i16(os2, 68, 800)
  set_i16(os2, 70, -200)
  let hhea = byte_array(tables["hhea"])
  set_i16(hhea, 4, 800)
  set_i16(hhea, 6, -200)
  tables["OS/2"] = Bytes::from_array(os2[:])
  tables["hhea"] = Bytes::from_array(hhea[:])
  tables["MVAR"] = metric_test_mvar(["hasc", "hdsc"])
  let source = build_sfnt(tables, 100000)
  let font = Font::parse(source)
  let output = font.instantiate({ "wght": 700.0 }).to_bytes()
  let result = parse_sfnt(output, 100000)
  assert_false(result.contains("MVAR"))
  assert_eq(read_i16(result["OS/2"], 68), 900)
  assert_eq(read_i16(result["OS/2"], 70), -250)
  assert_eq(read_i16(result["hhea"], 4), 900)
  assert_eq(read_i16(result["hhea"], 6), -250)
  assert_eq(font.instantiate({ "wght": 700.0 }).to_bytes(), output)
  assert_eq(read_i16(parse_sfnt(source, 100000)["OS/2"], 68), 800)
}

///|
test "MVAR overflow refuses one position and the font remains reusable" {
  let tables = api_fixture_tables()
  let os2 = byte_array(tables["OS/2"])
  set_i16(os2, 68, 32760)
  tables["OS/2"] = Bytes::from_array(os2[:])
  tables["MVAR"] = metric_test_mvar(["hasc"])
  let font = Font::parse(build_sfnt(tables, 100000))
  let original = font.instantiate({ "wght": 400.0 }).to_bytes()
  let rejected = try {
    ignore(font.instantiate({ "wght": 700.0 }))
    false
  } catch {
    Invalid(detail) => detail.contains("MVAR")
    _ => false
  }
  assert_true(rejected)
  assert_eq(font.instantiate({ "wght": 400.0 }).to_bytes(), original)
}
