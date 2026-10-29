///|
// Language strings are preserved, not translated or normalized. Check only
// ASCII subtag shape, not registration in the evolving IANA language registry.
fn validate_language_tag(data : Bytes, step : Int32) -> Unit raise FontError {
  if data.is_empty() || data.length() % step != 0 {
    raise Invalid("empty or truncated language tag")
  }
  let mut segment = 0
  let mut first = true
  for i in 0..<(data.length() / step) {
    let ch = if step == 2 { read_u16(data, i * 2) } else { read_u8(data, i) }
    if ch == 45 {
      if segment == 0 {
        raise Invalid("empty language subtag")
      }
      first = false
      segment = 0
    } else {
      let alpha = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
      if !alpha && (first || ch < 48 || ch > 57) {
        raise Invalid("non-ASCII or invalid language subtag")
      }
      segment += 1
      if segment > 8 {
        raise Invalid("language subtag exceeds eight characters")
      }
    }
  }
  if segment == 0 {
    raise Invalid("empty final language subtag")
  }
}

///|
fn validate_name_utf16(data : Bytes) -> Unit raise FontError {
  if data.length() % 2 != 0 {
    raise Invalid("odd-length UTF-16 name")
  }
  let mut position = 0
  while position < data.length() {
    let ch = read_u16(data, position)
    position += 2
    if ch >= 0xD800 && ch <= 0xDBFF {
      let low = read_u16(data, position)
      if low < 0xDC00 || low > 0xDFFF {
        raise Invalid("unpaired UTF-16 name surrogate")
      }
      position += 2
    } else if ch >= 0xDC00 && ch <= 0xDFFF {
      raise Invalid("unpaired UTF-16 name surrogate")
    }
  }
}

///|
// Apple ltag version 1: keep all bytes and numeric language associations.
// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6ltag.html
fn validate_ltag(tables : Map[String, Bytes]) -> Int32 raise FontError {
  guard tables.get("ltag") is Some(data) else { return 0 }
  if read_uint32(data, 0) != 1U || read_uint32(data, 4) != 0U {
    raise Unsupported("ltag version or flags")
  }
  let count = read_u32(data, 8)
  if count > 65535 {
    raise Limit("ltag count exceeds language ID range")
  }
  let header_size = 12 + count * 4
  require_range(data, 0, header_size)
  for i in 0..<count {
    let start = read_u16(data, 12 + i * 4)
    let length = read_u16(data, 14 + i * 4)
    if start < header_size {
      raise Invalid("ltag strings overlap records")
    }
    require_range(data, start, length)
    validate_language_tag(data[start:start + length].to_owned(), 1)
  }
  count
}
