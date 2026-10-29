///|
// Horizontal metrics variations: OpenType HVAR, version 1.0.
// https://learn.microsoft.com/en-us/typography/opentype/spec/hvar
fn apply_hvar(
  tables : Map[String, Bytes],
  coords : Array[Double],
  hmtx : Bytes,
  work_limit~ : Int32 = 20_000_000,
) -> Bytes raise FontError {
  guard tables.get("HVAR") is Some(data) else { return hmtx }
  require_range(data, 0, 20)
  if read_u16(data, 0) != 1 || read_u16(data, 2) != 0 {
    raise Unsupported("HVAR version is not 1.0")
  }
  let store_offset = read_u32(data, 4)
  if store_offset < 20 {
    raise Invalid("invalid HVAR variation store offset")
  }
  let store = variation_store(data, store_offset, coords, work_limit~)
  let advance_map = read_u32(data, 8)
  let lsb_map = read_u32(data, 12)
  let rsb_map = read_u32(data, 16)
  if rsb_map != 0 {
    raise Unsupported("HVAR right-side-bearing mappings are not yet supported")
  }
  if (advance_map != 0 && advance_map < 20) || (lsb_map != 0 && lsb_map < 20) {
    raise Invalid("invalid HVAR mapping offset")
  }
  if hmtx.length() % 4 != 0 {
    raise Invalid("instanced hmtx is not long-metrics format")
  }
  let glyphs = hmtx.length() / 4
  let hhea = table_required(tables, "hhea")
  let base = table_required(tables, "hmtx")
  let long_count = read_u16(hhea, 34)
  if long_count <= 0 || long_count > glyphs {
    raise Invalid("invalid original horizontal metric count")
  }
  let metric_bytes = long_count * 4 + (glyphs - long_count) * 2
  require_range(base, 0, metric_bytes)
  if base.length() != metric_bytes {
    raise Invalid("original hmtx contains bytes beyond its declared metrics")
  }
  let result = byte_array(hmtx)
  let mut work = 0
  for gid in 0..<glyphs {
    let (outer, inner) = if advance_map == 0 {
      (0, gid)
    } else {
      delta_index_map(data, advance_map, gid)
    }
    let adv_base = read_u16(
      base,
      (if gid < long_count { gid } else { long_count - 1 }) * 4,
    )
    let charge = variation_work(store, outer, inner)
    if charge > work_limit - work {
      raise Limit("HVAR delta evaluation budget exceeded")
    }
    work += charge
    let advance = adv_base.to_double() + variation_delta(store, outer, inner)
    if advance < -0.5 || advance >= 65535.5 {
      raise Invalid("HVAR advance overflows unsigned 16-bit range")
    }
    set_u16(result, gid * 4, ot_round(advance))
    if lsb_map != 0 {
      let (lsb_outer, lsb_inner) = delta_index_map(data, lsb_map, gid)
      let charge = variation_work(store, lsb_outer, lsb_inner)
      if charge > work_limit - work {
        raise Limit("HVAR delta evaluation budget exceeded")
      }
      work += charge
      let lsb_offset = if gid < long_count {
        gid * 4 + 2
      } else {
        long_count * 4 + (gid - long_count) * 2
      }
      let bearing = read_i16(base, lsb_offset).to_double() +
        variation_delta(store, lsb_outer, lsb_inner)
      if bearing < -32768.5 || bearing >= 32767.5 {
        raise Invalid("HVAR bearing overflows signed 16-bit range")
      }
      set_i16(result, gid * 4 + 2, ot_round(bearing))
    }
  }
  Bytes::from_array(result[:])
}
