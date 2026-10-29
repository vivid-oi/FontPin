///|
// OpenType tuple stores: https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats
// Behavioral reference: fontTools.ttLib.tables.TupleVariation (MIT).
priv struct GvarCursor {
  data : Bytes
  mut pos : Int32
  end : Int32
}

///|
fn GvarCursor::u8(self : GvarCursor) -> Int32 raise FontError {
  if self.pos >= self.end {
    raise Invalid("truncated gvar tuple payload")
  }
  let value = read_u8(self.data, self.pos)
  self.pos += 1
  value
}

///|
fn GvarCursor::u16(self : GvarCursor) -> Int32 raise FontError {
  if self.end - self.pos < 2 {
    raise Invalid("truncated gvar word")
  }
  let value = read_u16(self.data, self.pos)
  self.pos += 2
  value
}

///|
fn GvarCursor::f14(self : GvarCursor) -> Double raise FontError {
  let n = self.u16()
  (if n >= 32768 { n - 65536 } else { n }).to_double() / 16384.0
}

///|
fn packed_points(
  cursor : GvarCursor,
  point_count : Int32,
) -> Array[Int32]? raise FontError {
  let first = cursor.u8()
  let count = if (first & 128) != 0 {
    ((first & 127) << 8) | cursor.u8()
  } else {
    first
  }
  if count == 0 {
    return None
  }
  let points : Array[Int32] = []
  let mut current = 0
  while points.length() < count {
    let control = cursor.u8()
    let run = (control & 127) + 1
    if run > count - points.length() {
      raise Invalid("gvar point run exceeds declared count")
    }
    for _ in 0..<run {
      let difference = if (control & 128) != 0 {
        cursor.u16()
      } else {
        cursor.u8()
      }
      current += difference
      if current >= point_count {
        raise Invalid("gvar point number outside glyph")
      }
      points.push(current)
    }
  }
  Some(points)
}

///|
fn packed_deltas(
  cursor : GvarCursor,
  count : Int32,
) -> Array[Double] raise FontError {
  let values : Array[Double] = []
  while values.length() < count {
    let control = cursor.u8()
    let run = (control & 63) + 1
    if run > count - values.length() {
      raise Invalid("gvar delta run exceeds declared count")
    }
    for _ in 0..<run {
      let value = if (control & 128) != 0 {
        0
      } else if (control & 64) != 0 {
        let n = cursor.u16()
        if n >= 32768 {
          n - 65536
        } else {
          n
        }
      } else {
        let n = cursor.u8()
        if n >= 128 {
          n - 256
        } else {
          n
        }
      }
      values.push(value.to_double())
    }
  }
  values
}

///|
fn tuple_scalar(
  coords : Array[Double],
  peak : Array[Double],
  start : Array[Double]?,
  end : Array[Double]?,
) -> Double raise FontError {
  if coords.length() != peak.length() {
    raise Invalid("tuple axis count mismatch")
  }
  let mut scalar = 1.0
  for i, p in peak {
    let c = coords[i]
    if p < -1.0 || p > 1.0 {
      raise Invalid("gvar peak outside normalized range")
    }
    match (start, end) {
      (Some(lo), Some(hi)) => {
        if lo[i] < -1.0 || hi[i] > 1.0 || lo[i] > p || p > hi[i] {
          raise Invalid("invalid gvar intermediate region")
        }
        if p == 0.0 || (lo[i] < 0.0 && hi[i] > 0.0) {
          continue
        }
        if c < lo[i] || c > hi[i] {
          scalar = 0.0
          continue
        }
        if c < p && p != lo[i] {
          scalar *= (c - lo[i]) / (p - lo[i])
        }
        if c > p && p != hi[i] {
          scalar *= (hi[i] - c) / (hi[i] - p)
        }
      }
      (None, None) => {
        if p == 0.0 {
          continue
        }
        if c == 0.0 || (c < 0.0) != (p < 0.0) || c / p > 1.0 {
          scalar = 0.0
          continue
        }
        scalar *= c / p
      }
      _ => raise Invalid("incomplete gvar intermediate region")
    }
  }
  scalar
}

///|
fn iup_value(
  position : Double,
  a : Double,
  da : Double,
  b : Double,
  db : Double,
) -> Double {
  if a == b {
    return if da == db { da } else { 0.0 }
  }
  let (lo, dlo, hi, dhi) = if a < b { (a, da, b, db) } else { (b, db, a, da) }
  if position <= lo {
    dlo
  } else if position >= hi {
    dhi
  } else {
    dlo + (position - lo) * (dhi - dlo) / (hi - lo)
  }
}

///|
fn iup_contours(
  original : Array[Double],
  deltas : Array[Double],
  touched : Array[Bool],
  ends : Array[Int32],
) -> Unit {
  let mut first = 0
  for last in ends {
    let explicit : Array[Int32] = []
    for point in first..<=last {
      if touched[point] {
        explicit.push(point)
      }
    }
    if explicit.length() == 1 {
      let delta = deltas[explicit[0]]
      for point in first..<=last {
        deltas[point] = delta
      }
    } else if explicit.length() > 1 {
      for j, left in explicit {
        let right = explicit[(j + 1) % explicit.length()]
        let mut point = if left == last { first } else { left + 1 }
        while point != right {
          deltas[point] = iup_value(
            original[point],
            original[left],
            deltas[left],
            original[right],
            deltas[right],
          )
          point = if point == last { first } else { point + 1 }
        }
      }
    }
    first = last + 1
  }
}

///|
priv struct GvarTable {
  data : Bytes
  offsets : Array[Int32]
  shared : Array[Array[Double]]
  axis_count : Int32
}

///|
fn parse_gvar(
  data : Bytes,
  axis_count : Int32,
  glyph_count : Int32,
) -> GvarTable raise FontError {
  if read_u16(data, 0) != 1 || read_u16(data, 2) != 0 {
    raise Unsupported("gvar version other than 1.0")
  }
  if read_u16(data, 4) != axis_count || read_u16(data, 12) != glyph_count {
    raise Invalid("gvar axis or glyph count mismatch")
  }
  let shared_count = read_u16(data, 6)
  let shared_offset = read_u32(data, 8)
  let flags = read_u16(data, 14)
  if (flags & 65534) != 0 {
    raise Invalid("reserved gvar header flags")
  }
  let base = read_u32(data, 16)
  let width = if (flags & 1) != 0 { 4 } else { 2 }
  require_range(data, 20, (glyph_count + 1) * width)
  if base < 20 + (glyph_count + 1) * width {
    raise Invalid("gvar data overlaps offset array")
  }
  let offsets : Array[Int32] = []
  let mut previous = base
  for i in 0..<=glyph_count {
    let relative = if width == 4 {
      read_u32(data, 20 + i * 4)
    } else {
      2 * read_u16(data, 20 + i * 2)
    }
    if relative > data.length() - base {
      raise Invalid("gvar glyph data offset out of range")
    }
    let offset = base + relative
    if offset < previous {
      raise Invalid("non-monotonic gvar offsets")
    }
    offsets.push(offset)
    previous = offset
  }
  require_range(data, shared_offset, shared_count * axis_count * 2)
  if shared_count > 0 {
    let shared_end = shared_offset + shared_count * axis_count * 2
    if shared_offset < 20 + (glyph_count + 1) * width {
      raise Invalid("gvar shared tuples overlap the header or offset array")
    }
    for i in 0..<glyph_count {
      if offsets[i] < shared_end &&
        offsets[i + 1] > shared_offset &&
        offsets[i] != offsets[i + 1] {
        raise Invalid("gvar shared tuples overlap glyph tuple data")
      }
    }
  }
  let shared : Array[Array[Double]] = []
  for i in 0..<shared_count {
    shared.push(
      Array::makei(axis_count, j => {
        read_f2dot14(data, shared_offset + 2 * (i * axis_count + j))
      }),
    )
  }
  { data, offsets, shared, axis_count, }
}

///|
priv struct GlyphTuple {
  size : Int32
  peak : Array[Double]
  start : Array[Double]?
  end : Array[Double]?
  private_points : Bool
}

///|
fn apply_gvar(
  table : GvarTable,
  gid : Int32,
  coords : Array[Double],
  xs : Array[Double],
  ys : Array[Double],
  contour_ends : Array[Int32],
  work : Ref[Int32],
  work_limit : Int32,
) -> Unit raise FontError {
  let begin = table.offsets[gid]
  let finish = table.offsets[gid + 1]
  if begin == finish {
    return
  }
  let header : GvarCursor = { data: table.data, pos: begin, end: finish, }
  let count_flags = header.u16()
  if (count_flags & 28672) != 0 {
    raise Invalid("reserved gvar tuple count flags")
  }
  let count = count_flags & 4095
  let data_start = begin + header.u16()
  if data_start > finish {
    raise Invalid("gvar tuple data offset out of range")
  }
  let tuples : Array[GlyphTuple] = []
  for _ in 0..<count {
    let size = header.u16()
    let index = header.u16()
    if (index & 4096) != 0 {
      raise Invalid("reserved gvar tuple index flag")
    }
    let peak = if (index & 32768) != 0 {
      Array::makei(table.axis_count, _ => header.f14())
    } else {
      let shared_index = index & 4095
      if shared_index >= table.shared.length() {
        raise Invalid("gvar shared tuple index out of range")
      }
      table.shared[shared_index]
    }
    let (start, end) = if (index & 16384) != 0 {
      (
        Some(Array::makei(table.axis_count, _ => header.f14())),
        Some(Array::makei(table.axis_count, _ => header.f14())),
      )
    } else {
      (None, None)
    }
    tuples.push({ size, peak, start, end, private_points: (index & 8192) != 0, })
  }
  if header.pos > data_start {
    raise Invalid("gvar tuple headers overlap serialized data")
  }
  let payload : GvarCursor = { data: table.data, pos: data_start, end: finish, }
  let point_count = xs.length()
  let shared_points = if (count_flags & 32768) != 0 {
    packed_points(payload, point_count)
  } else {
    None
  }
  let result_x = Array::make(point_count, 0.0)
  let result_y = Array::make(point_count, 0.0)
  for tuple in tuples {
    if tuple.size > finish - payload.pos {
      raise Invalid("truncated gvar tuple data")
    }
    let block : GvarCursor = {
      data: table.data,
      pos: payload.pos,
      end: payload.pos + tuple.size,
    }
    payload.pos += tuple.size
    let points = if tuple.private_points {
      packed_points(block, point_count)
    } else {
      shared_points
    }
    let delta_count = match points {
      None => point_count
      Some(points) => points.length()
    }
    let dx = packed_deltas(block, delta_count)
    let dy = packed_deltas(block, delta_count)
    if block.pos != block.end {
      raise Invalid("extra bytes inside gvar tuple payload")
    }
    let scalar = tuple_scalar(coords, tuple.peak, tuple.start, tuple.end)
    let cost = if point_count > delta_count { point_count } else { delta_count }
    if cost > work_limit - work.val {
      raise Limit("gvar point-work budget exceeded")
    }
    work.val += cost
    let full_x = Array::make(point_count, 0.0)
    let full_y = Array::make(point_count, 0.0)
    match points {
      None =>
        for i in 0..<point_count {
          full_x[i] = dx[i]
          full_y[i] = dy[i]
        }
      Some(points) => {
        let touched = Array::make(point_count, false)
        for j, point in points {
          full_x[point] += dx[j]
          full_y[point] += dy[j]
          touched[point] = true
        }
        iup_contours(xs, full_x, touched, contour_ends)
        iup_contours(ys, full_y, touched, contour_ends)
      }
    }
    for i in 0..<point_count {
      result_x[i] += scalar * full_x[i]
      result_y[i] += scalar * full_y[i]
    }
  }
  for i in 0..<point_count {
    xs[i] += result_x[i]
    ys[i] += result_y[i]
  }
}
