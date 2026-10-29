///|
fn parse_axes(tables : Map[String, Bytes]) -> Array[Axis] raise FontError {
  let data = table_required(tables, "fvar")
  if read_u16(data, 0) != 1 || read_u16(data, 2) != 0 || read_u16(data, 6) != 2 {
    raise Unsupported("fvar version or reserved field")
  }
  let at = read_u16(data, 4)
  let n = read_u16(data, 8)
  let size = read_u16(data, 10)
  let instances = read_u16(data, 12)
  let instance_size = read_u16(data, 14)
  if n < 1 || n > 32 || size != 20 || at < 16 {
    raise Unsupported("fvar requires 1..32 axes and standard axis records")
  }
  if instance_size != 4 + 4 * n && instance_size != 6 + 4 * n {
    raise Invalid("invalid fvar instance record size")
  }
  require_range(data, at, n * size + instances * instance_size)
  if at + n * size + instances * instance_size != data.length() {
    raise Unsupported("fvar trailing extension bytes")
  }
  for i in 16..<at {
    if data[i] != 0 {
      raise Unsupported("fvar extension bytes before axes")
    }
  }
  let axes : Array[Axis] = []
  let seen : Map[String, Bool] = Map([])
  for i in 0..<n {
    let p = at + i * size
    let tag = read_tag(data, p)
    if seen.contains(tag) {
      raise Invalid("duplicate axis: " + tag)
    }
    seen[tag] = true
    let minimum = read_fixed(data, p + 4)
    let default = read_fixed(data, p + 8)
    let maximum = read_fixed(data, p + 12)
    if minimum > default || default > maximum || minimum == maximum {
      raise Invalid("invalid axis range: " + tag)
    }
    if (read_u16(data, p + 16) & 0xFFFE) != 0 {
      raise Unsupported("unknown axis flags")
    }
    axes.push({ tag, minimum, default, maximum, })
  }
  axes
}

///|
fn normalized_coordinates(
  font : Font,
  coordinates : Map[String, Double],
) -> (Array[Double], Map[String, Double]) raise FontError {
  for tag, value in coordinates {
    if value.is_nan() || value.is_inf() {
      raise Invalid("axis value must be finite: " + tag)
    }
    if !font.design_axes.any(axis => axis.tag == tag) {
      raise Invalid("unknown axis: " + tag)
    }
  }
  let normalized : Array[Double] = []
  let actual : Map[String, Double] = Map([])
  for axis in font.design_axes {
    let value = coordinates.get(axis.tag).unwrap_or(axis.default)
    if value < axis.minimum || value > axis.maximum {
      raise Invalid("axis out of range: " + axis.tag)
    }
    actual[axis.tag] = value
    let v = if value == axis.default {
      0.0
    } else if value < axis.default {
      (value - axis.default) / (axis.default - axis.minimum)
    } else {
      (value - axis.default) / (axis.maximum - axis.default)
    }
    normalized.push(v)
  }
  if font.tables.get("avar") is Some(data) {
    if read_u16(data, 0) != 1 || read_u16(data, 2) != 0 {
      raise Unsupported("only avar version 1.0 is supported")
    }
    if read_u16(data, 4) != 0 || read_u16(data, 6) != normalized.length() {
      raise Invalid("avar axis count or reserved field")
    }
    let mut p = 8
    for i in 0..<normalized.length() {
      let n = read_u16(data, p)
      p += 2
      if n < 3 || n > 16384 {
        raise Invalid("avar requires at least three anchor pairs")
      }
      require_range(data, p, n * 4)
      let mut last_x = -2.0
      let mut last_y = -2.0
      let mut has_zero = false
      let mut result = normalized[i]
      for j in 0..<n {
        let x = read_f2dot14(data, p + j * 4)
        let y = read_f2dot14(data, p + j * 4 + 2)
        if x <= last_x ||
          x < -1.0 ||
          x > 1.0 ||
          y < last_y ||
          y < -1.0 ||
          y > 1.0 {
          raise Invalid("invalid avar mapping")
        }
        if j == 0 && (x != -1.0 || y != -1.0) {
          raise Invalid("avar missing -1 anchor")
        }
        if j == n - 1 && (x != 1.0 || y != 1.0) {
          raise Invalid("avar missing +1 anchor")
        }
        if x == 0.0 {
          if y != 0.0 {
            raise Invalid("avar zero anchor")
          }
          has_zero = true
        }
        if j > 0 && normalized[i] >= last_x && normalized[i] <= x {
          result = last_y +
            (normalized[i] - last_x) / (x - last_x) * (y - last_y)
        }
        last_x = x
        last_y = y
      }
      if !has_zero {
        raise Invalid("avar missing zero anchor")
      }
      normalized[i] = result
      p += n * 4
    }
    if p != data.length() {
      raise Invalid("trailing avar data")
    }
  }
  for i in 0..<normalized.length() {
    normalized[i] = ot_round(normalized[i] * 16384.0).to_double() / 16384.0
  }
  (normalized, actual)
}
