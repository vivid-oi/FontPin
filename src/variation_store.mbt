///|
// ItemVariationStore and DeltaSetIndexMap follow OpenType 1.9.1:
// https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats
priv struct VariationRow {
  offset : Int32
  count : Int32
  row_size : Int32
  wide_count : Int32
  long_words : Bool
  regions : Array[Int32]
}

///|
priv struct VariationStore {
  bytes : Bytes
  scalars : Array[Double]
  rows : Array[VariationRow]
}

///|
fn iv_span(
  data : Bytes,
  pos : Int32,
  count : Int32,
  width : Int32,
) -> Unit raise FontError {
  require_range(data, pos, 0)
  if count < 0 || width <= 0 || count > (data.length() - pos) / width {
    raise Invalid("truncated variation array")
  }
}

///|
fn variation_store(
  data : Bytes,
  base : Int32,
  coords : Array[Double],
  work_limit~ : Int32 = 20_000_000,
) -> VariationStore raise FontError {
  require_range(data, base, 8)
  if coords.length() > 64 {
    raise Limit("more than 64 variation axes")
  }
  for c in coords {
    if c != c || c < -1.0 || c > 1.0 {
      raise Invalid("invalid normalized variation coordinate")
    }
  }
  if read_u16(data, base) != 1 {
    raise Unsupported("ItemVariationStore format is not 1")
  }
  let region_offset = read_u32(data, base + 2)
  let row_count = read_u16(data, base + 6)
  iv_span(data, base + 8, row_count, 4)
  if region_offset < 8 + row_count * 4 || region_offset > data.length() - base {
    raise Invalid("invalid VariationRegionList offset")
  }
  let region_base = base + region_offset
  let axes = read_u16(data, region_base)
  let regions = read_u16(data, region_base + 2)
  if axes != coords.length() || regions >= 32768 {
    raise Invalid("variation region axis or region count mismatch")
  }
  if work_limit < 1 || axes * regions > work_limit {
    raise Limit("variation region scalar budget exceeded")
  }
  if axes > 0 {
    iv_span(data, region_base + 4, regions, axes * 6)
  }
  let scalars : Array[Double] = []
  for r in 0..<regions {
    let mut scalar = 1.0
    for a in 0..<axes {
      let p = region_base + 4 + (r * axes + a) * 6
      let start = read_f2dot14(data, p)
      let peak = read_f2dot14(data, p + 2)
      let end = read_f2dot14(data, p + 4)
      if start < -1.0 ||
        end > 1.0 ||
        start > peak ||
        peak > end ||
        (peak != 0.0 && start < 0.0 && end > 0.0) {
        raise Invalid("invalid variation region coordinates")
      }
      let c = coords[a]
      if peak == 0.0 {
        ()
      } else if c == peak {
        ()
      } else if c <= start || c >= end {
        scalar = 0.0
      } else if c < peak {
        scalar *= (c - start) / (peak - start)
      } else {
        scalar *= (end - c) / (end - peak)
      }
    }
    scalars.push(scalar)
  }
  let rows : Array[VariationRow] = []
  let mut column_work = axes * regions
  for i in 0..<row_count {
    let offset = read_u32(data, base + 8 + i * 4)
    if offset < 8 + row_count * 4 || offset > data.length() - base {
      raise Invalid("invalid ItemVariationData offset")
    }
    let row_base = base + offset
    require_range(data, row_base, 6)
    let count = read_u16(data, row_base)
    let number_words = read_u16(data, row_base + 2)
    let wide_count = number_words & 32767
    let long_words = (number_words & 32768) != 0
    let region_count = read_u16(data, row_base + 4)
    if wide_count > region_count {
      raise Invalid("variation wide delta count exceeds region count")
    }
    column_work += region_count
    if column_work > work_limit {
      raise Limit("variation region index budget exceeded")
    }
    iv_span(data, row_base + 6, region_count, 2)
    let indices : Array[Int32] = []
    for j in 0..<region_count {
      let index = read_u16(data, row_base + 6 + j * 2)
      if index >= regions {
        raise Invalid("variation region index out of bounds")
      }
      indices.push(index)
    }
    let row_size = if long_words {
      wide_count * 4 + (region_count - wide_count) * 2
    } else {
      wide_count * 2 + region_count - wide_count
    }
    let data_offset = row_base + 6 + region_count * 2
    if row_size > 0 {
      iv_span(data, data_offset, count, row_size)
    }
    rows.push({
      offset: data_offset,
      count,
      row_size,
      wide_count,
      long_words,
      regions: indices,
    })
  }
  { bytes: data, scalars, rows, }
}

///|
fn variation_work(
  store : VariationStore,
  outer : Int32,
  inner : Int32,
) -> Int32 raise FontError {
  if outer == 65535 && inner == 65535 {
    return 0
  }
  if outer < 0 || outer >= store.rows.length() {
    raise Invalid("variation outer index out of bounds")
  }
  let row = store.rows[outer]
  if inner < 0 || inner >= row.count {
    raise Invalid("variation inner index out of bounds")
  }
  row.regions.length()
}

///|
fn variation_delta(
  store : VariationStore,
  outer : Int32,
  inner : Int32,
) -> Double raise FontError {
  if outer == 65535 && inner == 65535 {
    return 0.0
  }
  if outer < 0 || outer >= store.rows.length() {
    raise Invalid("variation outer index out of bounds")
  }
  let row = store.rows[outer]
  if inner < 0 || inner >= row.count {
    raise Invalid("variation inner index out of bounds")
  }
  let mut p = row.offset + inner * row.row_size
  let mut total = 0.0
  for col, region in row.regions {
    let value = if row.long_words && col < row.wide_count {
      let v = read_uint32(store.bytes, p).reinterpret_as_int()
      p += 4
      v
    } else if row.long_words || col < row.wide_count {
      let v = read_i16(store.bytes, p)
      p += 2
      v
    } else {
      let v = read_u8(store.bytes, p)
      p += 1
      if v >= 128 {
        v - 256
      } else {
        v
      }
    }
    total += value.to_double() * store.scalars[region]
  }
  total
}

///|
fn delta_index_map(
  data : Bytes,
  offset : Int32,
  glyph : Int32,
) -> (Int32, Int32) raise FontError {
  require_range(data, offset, 4)
  let format = read_u8(data, offset)
  let entry_format = read_u8(data, offset + 1)
  if (entry_format & 192) != 0 {
    raise Invalid("reserved delta index map entry bits")
  }
  let (count, header) = match format {
    0 => (read_u16(data, offset + 2), 4)
    1 => (read_u32(data, offset + 2), 6)
    _ => raise Unsupported("DeltaSetIndexMap format is not 0 or 1")
  }
  let size = ((entry_format >> 4) & 3) + 1
  let inner_bits = (entry_format & 15) + 1
  if count <= 0 || glyph < 0 || inner_bits > size * 8 {
    raise Invalid("invalid delta index map count or entry format")
  }
  iv_span(data, offset + header, count, size)
  let index = if glyph >= count { count - 1 } else { glyph }
  let mut packed = 0U
  for i in 0..<size {
    packed = (packed << 8) |
      read_u8(data, offset + header + index * size + i).reinterpret_as_uint()
  }
  let outer = packed >> inner_bits
  let inner = packed & ((1U << inner_bits) - 1U)
  if outer > 65535U {
    raise Invalid("delta map outer index exceeds 16 bits")
  }
  (outer.reinterpret_as_int(), inner.reinterpret_as_int())
}
