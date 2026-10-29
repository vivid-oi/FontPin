///|
fn checksum(data : Bytes, head~ : Bool = false) -> UInt32 {
  let mut sum = 0U
  for pos = 0; pos < data.length(); pos = pos + 4 {
    let mut word = 0U
    for i in 0..<4 {
      let at = pos + i
      let b = if at >= data.length() || (head && at >= 8 && at < 12) {
        0U
      } else {
        data[at].to_uint()
      }
      word = (word << 8) | b
    }
    sum += word
  }
  sum
}

///|
fn parse_sfnt(
  data : Bytes,
  max_bytes : Int32,
) -> Map[String, Bytes] raise FontError {
  if max_bytes < 12 || max_bytes > 128 * 1024 * 1024 {
    raise Limit("max_bytes must be between 12 and 134217728")
  }
  if data.length() > max_bytes {
    raise Limit("font exceeds max_bytes")
  }
  if read_uint32(data, 0) != 0x00010000U {
    raise Unsupported(
      "expected a single sfnt TrueType font (not CFF, WOFF or a collection)",
    )
  }
  let n = read_u16(data, 4)
  if n < 1 || n > 128 {
    raise Limit("table count must be 1..128")
  }
  require_range(data, 12, n * 16)
  let tables : Map[String, Bytes] = Map([])
  let spans : Array[(Int32, Int32)] = []
  let mut previous = ""
  for i in 0..<n {
    let p = 12 + 16 * i
    let tag = read_tag(data, p)
    if tag.lexical_compare(previous) <= 0 {
      raise Invalid("table directory must be unique and lexically sorted")
    }
    previous = tag
    let start = read_u32(data, p + 8)
    let size = read_u32(data, p + 12)
    require_range(data, start, size)
    if start % 4 != 0 || start < 12 + n * 16 {
      raise Invalid("unaligned table or table overlaps directory: " + tag)
    }
    for (a, b) in spans {
      if size > 0 && start < b && start + size > a {
        raise Invalid("overlapping font tables")
      }
    }
    spans.push((start, start + size))
    let body = data[start:start + size].to_owned()
    if checksum(body, head=tag == "head") != read_uint32(data, p + 4) {
      raise Invalid("table checksum mismatch: " + tag)
    }
    tables[tag] = body
  }
  spans.sort_by((a, b) => a.0.compare(b.0))
  let mut consumed = 12 + n * 16
  for (start, end) in spans {
    if start > consumed {
      for i in consumed..<start {
        if data[i] != 0 {
          raise Invalid("nonzero bytes outside declared sfnt tables")
        }
      }
    }
    if end > consumed {
      consumed = end
    }
  }
  for i in consumed..<data.length() {
    if data[i] != 0 {
      raise Invalid("nonzero bytes after declared sfnt tables")
    }
  }
  if checksum(data) != 0xB1B0AFBAU {
    raise Invalid("whole-font checksum mismatch")
  }
  let head = table_required(tables, "head")
  require_range(head, 0, 54)
  if read_uint32(head, 12) != 0x5F0F3CF5U {
    raise Invalid("invalid head magic number")
  }
  let upem = read_u16(head, 18)
  if upem < 16 || upem > 16384 {
    raise Invalid("unitsPerEm must be 16..16384")
  }
  if read_i16(head, 50) < 0 || read_i16(head, 50) > 1 {
    raise Invalid("invalid loca format")
  }
  let maxp = table_required(tables, "maxp")
  require_range(maxp, 0, 32)
  if read_uint32(maxp, 0) != 0x00010000U || read_u16(maxp, 4) == 0 {
    raise Invalid("expected nonempty TrueType maxp 1.0")
  }
  for tag in ["hhea", "hmtx", "loca", "glyf", "cmap", "name", "OS/2", "post"] {
    ignore(table_required(tables, tag))
  }
  tables
}

///|
fn build_sfnt(
  tables : Map[String, Bytes],
  max_bytes : Int32,
) -> Bytes raise FontError {
  let tags = tables.keys().to_array()
  tags.sort_by((a, b) => a.lexical_compare(b))
  let n = tags.length()
  let mut total = 12 + n * 16
  for tag in tags {
    let len = tables[tag].length()
    if len > max_bytes - total - 3 {
      raise Limit("output font exceeds max_bytes")
    }
    total += (len + 3) / 4 * 4
  }
  let out : Array[Byte] = Array::make(total, 0)
  set_u32(out, 0, 0x00010000U)
  set_u16(out, 4, n)
  let mut power = 1
  let mut selector = 0
  while power * 2 <= n {
    power *= 2
    selector += 1
  }
  set_u16(out, 6, power * 16)
  set_u16(out, 8, selector)
  set_u16(out, 10, n * 16 - power * 16)
  let mut at = 12 + n * 16
  let mut head_at = -1
  for i, tag in tags {
    let p = 12 + i * 16
    let bytes = tables[tag]
    for j in 0..<4 {
      out[p + j] = tag[j].to_int().to_byte()
    }
    set_u32(out, p + 4, checksum(bytes, head=tag == "head"))
    set_u32(out, p + 8, at.reinterpret_as_uint())
    set_u32(out, p + 12, bytes.length().reinterpret_as_uint())
    for j in 0..<bytes.length() {
      out[at + j] = bytes[j]
    }
    if tag == "head" {
      head_at = at
      set_u32(out, at + 8, 0U)
    }
    at += (bytes.length() + 3) / 4 * 4
  }
  if head_at < 0 {
    raise Invalid("missing head")
  }
  set_u32(out, head_at + 8, 0xB1B0AFBAU - checksum(Bytes::from_array(out[:])))
  Bytes::from_array(out[:])
}
