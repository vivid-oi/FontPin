///|
// OpenType cvar uses tuple variation stores with one delta per CVT index.
// It shares gvar's tuple decoding but intentionally does not apply IUP.
// https://learn.microsoft.com/en-us/typography/opentype/spec/cvar
fn apply_cvar(
  tables : Map[String, Bytes],
  coords : Array[Double],
  work_limit~ : Int32 = 20_000_000,
) -> Unit raise FontError {
  guard tables.get("cvar") is Some(data) else { return }
  let cvt = table_required(tables, "cvt ")
  if cvt.length() % 2 != 0 {
    raise Invalid("cvt table length is not even")
  }
  let point_count = cvt.length() / 2
  if point_count > 65535 || coords.length() > 64 {
    raise Limit("cvar control value or axis budget exceeded")
  }
  for c in coords {
    if c != c || c < -1.0 || c > 1.0 {
      raise Invalid("invalid normalized cvar coordinate")
    }
  }
  require_range(data, 0, 8)
  if read_u16(data, 0) != 1 || read_u16(data, 2) != 0 {
    raise Unsupported("cvar version is not 1.0")
  }
  let count_flags = read_u16(data, 4)
  if (count_flags & 28672) != 0 {
    raise Invalid("reserved cvar tuple count flags")
  }
  let count = count_flags & 4095
  if count == 0 {
    raise Invalid("cvar has no variation tuples")
  }
  // Account for CVT initialization/write-back and the worst-case tuple axis
  // records before allocating or evaluating variation arrays.
  let mut work = point_count * 2 + count * (coords.length() * 3 + 1)
  if work_limit < 1 || work > work_limit {
    raise Limit("cvar point-work budget exceeded")
  }
  let data_start = read_u16(data, 6)
  if data_start < 8 || data_start > data.length() {
    raise Invalid("cvar serialized data offset is out of bounds")
  }
  let header : GvarCursor = { data, pos: 8, end: data_start, }
  let tuples : Array[GlyphTuple] = []
  for _ in 0..<count {
    let size = header.u16()
    let index = header.u16()
    if (index & 32768) == 0 {
      raise Invalid("cvar requires an embedded peak tuple")
    }
    if (index & 4096) != 0 {
      raise Invalid("reserved cvar tuple index flag")
    }
    let peak = Array::makei(coords.length(), _ => header.f14())
    let (start, end) = if (index & 16384) != 0 {
      (
        Some(Array::makei(coords.length(), _ => header.f14())),
        Some(Array::makei(coords.length(), _ => header.f14())),
      )
    } else {
      (None, None)
    }
    tuples.push({ size, peak, start, end, private_points: (index & 8192) != 0, })
  }
  if data_start - header.pos > 3 {
    raise Invalid("unexplained bytes before cvar serialized data")
  }
  for i in header.pos..<data_start {
    if data[i] != 0 {
      raise Invalid("nonzero bytes before cvar serialized data")
    }
  }
  let payload : GvarCursor = { data, pos: data_start, end: data.length(), }
  let shared_points = if (count_flags & 32768) != 0 {
    packed_points(payload, point_count)
  } else {
    None
  }
  if shared_points is Some(points) {
    if points.length() > work_limit - work {
      raise Limit("cvar shared point-work budget exceeded")
    }
    work += points.length()
  }
  let deltas = Array::make(point_count, 0.0)
  for tuple in tuples {
    if tuple.size > payload.end - payload.pos {
      raise Invalid("truncated cvar tuple data")
    }
    let block : GvarCursor = {
      data,
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
    let charge = if delta_count > point_count {
      delta_count
    } else {
      point_count
    }
    if charge > work_limit - work {
      raise Limit("cvar point-work budget exceeded")
    }
    work += charge
    let values = packed_deltas(block, delta_count)
    if block.pos != block.end {
      raise Invalid("extra bytes in cvar tuple payload")
    }
    let scalar = tuple_scalar(coords, tuple.peak, tuple.start, tuple.end)
    match points {
      None =>
        for i in 0..<point_count {
          deltas[i] += scalar * values[i]
        }
      Some(points) =>
        for i, point in points {
          deltas[point] += scalar * values[i]
        }
    }
  }
  // Neither table padding nor future unexplained tuple data is discarded.
  if payload.pos != payload.end {
    raise Invalid("extra bytes after cvar tuple data")
  }
  let result = byte_array(cvt)
  for i, delta in deltas {
    let value = read_i16(cvt, i * 2).to_double() + delta
    if value < -32768.5 || value >= 32767.5 {
      raise Invalid("cvar control value overflows signed 16-bit range")
    }
    set_i16(result, i * 2, ot_round(value))
  }
  tables["cvt "] = Bytes::from_array(result[:])
}
