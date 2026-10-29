///|
fn update_instance_names(
  tables : Map[String, Bytes],
  coordinates : Map[String, Double],
) -> Unit raise FontError {
  let source = table_required(tables, "name")
  if read_u16(source, 0) != 0 {
    raise Unsupported("name table format 1 language tags")
  }
  let n = read_u16(source, 2)
  let base = read_u16(source, 4)
  require_range(source, 6, n * 12)
  if base < 6 + n * 12 {
    raise Invalid("name strings overlap records")
  }
  let tags = coordinates.keys().to_array()
  tags.sort_by((a, b) => a.lexical_compare(b))
  let parts : Array[String] = []
  for tag in tags {
    parts.push(tag + coordinates[tag].to_string())
  }
  let style = parts.join("-")
  let records : Array[Byte] = Array::make(6 + n * 12, 0)
  let strings : Array[Byte] = []
  set_u16(records, 2, n)
  set_u16(records, 4, records.length())
  for i in 0..<n {
    let p = 6 + i * 12
    let platform = read_u16(source, p)
    let id = read_u16(source, p + 6)
    let len = read_u16(source, p + 8)
    let offset = read_u16(source, p + 10)
    require_range(source, base + offset, len)
    let original = source[base + offset:base + offset + len].to_owned()
    let replace = [2, 3, 4, 6, 17].contains(id)
    let value = if replace {
      let label = if id == 6 {
        "-" + style.replace_all(old=".", new="_")
      } else if id == 3 {
        ";" + style
      } else if id == 4 {
        " " + style
      } else {
        style
      }
      // Keep each font's existing identity prefix, including its encoding and
      // language, so unrelated families pinned to the same axes cannot collide.
      let encoded : Array[Byte] = if [3, 4, 6].contains(id) {
        byte_array(original)
      } else {
        []
      }
      if id == 6 {
        let step = if platform == 0 || platform == 3 { 2 } else { 1 }
        if original.length() == 0 ||
          original.length() % step != 0 ||
          original.length() / step + label.length() > 63 {
          raise Unsupported(
            "PostScript instance name must fit 63 ASCII characters",
          )
        }
        for j in 0..<(original.length() / step) {
          let ch = if step == 2 {
            read_u16(original, j * step)
          } else {
            read_u8(original, j)
          }
          if ch < 33 ||
            ch > 126 ||
            "[](){}<>/%".contains(ch.unsafe_to_char().to_string()) {
            raise Invalid("invalid PostScript name")
          }
        }
        for ch in label {
          if ch.to_int() < 33 ||
            ch.to_int() > 126 ||
            "[](){}<>/%".contains(ch.to_string()) {
            raise Unsupported("axis label cannot form a PostScript name")
          }
        }
      }
      for ch in label {
        if platform == 0 || platform == 3 {
          push_u16(encoded, ch.to_int())
        } else if platform == 1 {
          encoded.push(ch.to_int().to_byte())
        } else {
          raise Unsupported("name platform on rewritten record")
        }
      }
      Bytes::from_array(encoded[:])
    } else {
      original
    }
    for j in 0..<8 {
      records[p + j] = source[p + j]
    }
    set_u16(records, p + 8, value.length())
    set_u16(records, p + 10, strings.length())
    for b in value {
      strings.push(b)
    }
  }
  for b in strings {
    records.push(b)
  }
  tables["name"] = Bytes::from_array(records[:])
  let os2 = byte_array(table_required(tables, "OS/2"))
  require_range(Bytes::from_array(os2[:]), 0, 78)
  if coordinates.get("wght") is Some(weight) {
    let w = ot_round(weight)
    set_u16(os2, 4, if w < 1 { 1 } else if w > 1000 { 1000 } else { w })
  }
  if coordinates.get("wdth") is Some(width) {
    let classes = [50.0, 62.5, 75.0, 87.5, 100.0, 112.5, 125.0, 150.0, 200.0]
    let mut best = 4
    let mut distance = 1.0e20
    for i, value in classes {
      let d = if value > width { value - width } else { width - value }
      if d < distance {
        best = i
        distance = d
      }
    }
    set_u16(os2, 6, best + 1)
  }
  let bold = read_u16(Bytes::from_array(os2[:]), 4) >= 700
  let old_flags = read_u16(Bytes::from_array(os2[:]), 62)
  let italic = if coordinates.get("ital") is Some(v) {
    v >= 0.5
  } else if coordinates.get("slnt") is Some(v) {
    v != 0.0
  } else {
    (old_flags & 1) != 0
  }
  let mut flags = old_flags & 0xFF9E
  if bold {
    flags = flags | 32
  }
  if italic {
    flags = flags | 1
  }
  if !bold && !italic {
    flags = flags | 64
  }
  set_u16(os2, 62, flags)
  tables["OS/2"] = Bytes::from_array(os2[:])
  if coordinates.get("slnt") is Some(angle) {
    let post = byte_array(table_required(tables, "post"))
    let fixed = ot_round(angle * 65536.0)
    set_u32(post, 4, fixed.reinterpret_as_uint())
    tables["post"] = Bytes::from_array(post[:])
  }
  let head = byte_array(tables["head"])
  let mut mac_style = read_u16(tables["head"], 44) & 0xFFFC
  if bold {
    mac_style = mac_style | 1
  }
  if italic {
    mac_style = mac_style | 2
  }
  set_u16(head, 44, mac_style)
  tables["head"] = Bytes::from_array(head[:])
}
