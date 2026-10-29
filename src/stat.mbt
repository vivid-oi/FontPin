///|
fn update_stat(
  tables : Map[String, Bytes],
  coordinates : Map[String, Double],
) -> Unit raise FontError {
  guard tables.get("STAT") is Some(data) else { return }
  if read_u16(data, 0) != 1 {
    raise Unsupported("STAT major version")
  }
  let minor = read_u16(data, 2)
  if minor > 2 {
    raise Unsupported("STAT minor version")
  }
  let axis_size = read_u16(data, 4)
  let axis_count = read_u16(data, 6)
  let axis_offset = read_u32(data, 8)
  let value_count = read_u16(data, 12)
  let value_offset = read_u32(data, 14)
  let header_size = if minor == 0 { 18 } else { 20 }
  require_range(data, 0, header_size)
  if axis_size != 8 || axis_count > 64 {
    raise Unsupported("STAT axis records")
  }
  require_range(data, axis_offset, axis_size * axis_count)
  require_range(data, value_offset, value_count * 2)
  let values : Array[Bytes] = []
  let axis_value = fn(index : Int32) -> Double? raise FontError {
    if index >= axis_count {
      raise Invalid("STAT axis index")
    }
    let tag = read_tag(data, axis_offset + index * 8)
    coordinates.get(tag)
  }
  for i in 0..<value_count {
    let p = value_offset + read_u16(data, value_offset + i * 2)
    let format = read_u16(data, p)
    let (length, keep) = match format {
      1 => {
        let reference = read_fixed(data, p + 8)
        (
          12,
          match axis_value(read_u16(data, p + 2)) {
            Some(value) => value == reference
            None => true
          },
        )
      }
      2 => {
        let lower = read_fixed(data, p + 12)
        let upper = read_fixed(data, p + 16)
        if lower > upper {
          raise Invalid("STAT inverted range")
        }
        (
          20,
          match axis_value(read_u16(data, p + 2)) {
            Some(value) => value >= lower && value <= upper
            None => true
          },
        )
      }
      3 => {
        let reference = read_fixed(data, p + 8)
        (
          16,
          match axis_value(read_u16(data, p + 2)) {
            Some(value) => value == reference
            None => true
          },
        )
      }
      4 => {
        let count = read_u16(data, p + 2)
        if count > axis_count {
          raise Invalid("STAT multiaxis value count")
        }
        let mut keep = true
        for j in 0..<count {
          let reference = read_fixed(data, p + 10 + j * 6)
          if axis_value(read_u16(data, p + 8 + j * 6)) is Some(value) &&
            value != reference {
            keep = false
          }
        }
        (8 + count * 6, keep)
      }
      _ => raise Unsupported("STAT axis value format")
    }
    require_range(data, p, length)
    if keep {
      values.push(data[p:p + length].to_owned())
    }
  }
  let out = byte_array(data[:header_size].to_owned())
  set_u32(out, 8, header_size.reinterpret_as_uint())
  for b in data[axis_offset:axis_offset + axis_count * axis_size] {
    out.push(b)
  }
  let start = out.length()
  set_u16(out, 12, values.length())
  set_u32(
    out,
    14,
    if values.is_empty() {
      0U
    } else {
      start.reinterpret_as_uint()
    },
  )
  let mut offset = values.length() * 2
  for value in values {
    push_u16(out, offset)
    offset += value.length()
  }
  for value in values {
    for b in value {
      out.push(b)
    }
  }
  tables["STAT"] = Bytes::from_array(out[:])
}
