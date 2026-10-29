///|
// VVAR is evaluated against original vmtx, never the already-varied phantom
// metrics. TrueType vertical-origin maps are outside this implementation.
// https://learn.microsoft.com/en-us/typography/opentype/spec/vvar
fn vvar_delta(
  data : Bytes,
  store : VariationStore,
  map : Int32,
  gid : Int32,
  work : Ref[Int32],
  work_limit : Int32,
) -> Double raise FontError {
  let (outer, inner) = if map == 0 {
    (0, gid)
  } else {
    delta_index_map(data, map, gid)
  }
  let charge = variation_work(store, outer, inner)
  if charge > work_limit - work.val {
    raise Limit("VVAR delta evaluation budget exceeded")
  }
  work.val += charge
  variation_delta(store, outer, inner)
}

///|
fn metric_outline_size(
  tables : Map[String, Bytes],
  gid : Int32,
  vertical : Bool,
) -> Int32 raise FontError {
  let loca = table_required(tables, "loca")
  let short = read_i16(table_required(tables, "head"), 50) == 0
  let start = if short {
    read_u16(loca, gid * 2) * 2
  } else {
    read_u32(loca, gid * 4)
  }
  let end = if short {
    read_u16(loca, gid * 2 + 2) * 2
  } else {
    read_u32(loca, gid * 4 + 4)
  }
  if start == end {
    return 0
  }
  let glyf = table_required(tables, "glyf")
  if vertical {
    read_i16(glyf, start + 8) - read_i16(glyf, start + 4)
  } else {
    read_i16(glyf, start + 6) - read_i16(glyf, start + 2)
  }
}

///|
fn instanced_outline_size(
  glyphs : GlyphResult,
  gid : Int32,
  vertical : Bool,
) -> Int32 raise FontError {
  let start = read_u32(glyphs.loca, gid * 4)
  let end = read_u32(glyphs.loca, gid * 4 + 4)
  if start == end {
    return 0
  }
  if vertical {
    read_i16(glyphs.glyf, start + 8) - read_i16(glyphs.glyf, start + 4)
  } else {
    read_i16(glyphs.glyf, start + 6) - read_i16(glyphs.glyf, start + 2)
  }
}

///|
fn apply_vvar(
  tables : Map[String, Bytes],
  coords : Array[Double],
  glyphs : GlyphResult,
  work_limit : Int32,
) -> Bytes? raise FontError {
  guard tables.get("VVAR") is Some(data) else { return glyphs.vmtx }
  guard glyphs.vmtx is Some(phantom) else {
    raise Invalid("VVAR requires vhea and vmtx")
  }
  require_range(data, 0, 24)
  if read_uint32(data, 0) != 0x00010000U {
    raise Unsupported("VVAR version is not 1.0")
  }
  let store_at = read_u32(data, 4)
  if store_at < 24 {
    raise Invalid("VVAR store overlaps its header")
  }
  let advance_map = read_u32(data, 8)
  let top_map = read_u32(data, 12)
  let bottom_map = read_u32(data, 16)
  if read_u32(data, 20) != 0 {
    raise Unsupported("VVAR vertical-origin mapping in TrueType font")
  }
  for offset in [advance_map, top_map, bottom_map] {
    if offset != 0 {
      if offset < 24 {
        raise Invalid("VVAR map overlaps its header")
      }
      if read_u8(data, offset) != 0 {
        raise Unsupported("VVAR requires DeltaSetIndexMap format 0")
      }
    }
  }
  let store = variation_store(data, store_at, coords, work_limit~)
  guard vertical_metrics(tables, glyphs.glyph_count) is Some((base, count)) else {
    raise Invalid("VVAR requires original vertical metrics")
  }
  let result = byte_array(phantom)
  let work = Ref(0)
  for gid in 0..<glyphs.glyph_count {
    let (old_advance, old_top) = glyph_metrics(base, gid, count)
    let advance = old_advance.to_double() +
      vvar_delta(data, store, advance_map, gid, work, work_limit)
    if advance < -0.5 || advance >= 65535.5 {
      raise Invalid("VVAR advance overflows unsigned 16-bit range")
    }
    let new_advance = ot_round(advance)
    let height = instanced_outline_size(glyphs, gid, true)
    let mut top = if top_map == 0 {
      read_i16(phantom, gid * 4 + 2).to_double()
    } else {
      old_top.to_double() +
      vvar_delta(data, store, top_map, gid, work, work_limit)
    }
    if bottom_map != 0 {
      let old_bottom = old_advance -
        old_top -
        metric_outline_size(tables, gid, true)
      let bottom = old_bottom.to_double() +
        vvar_delta(data, store, bottom_map, gid, work, work_limit)
      if bottom < -2147483648.0 || bottom > 2147483647.0 {
        raise Invalid("VVAR bottom bearing overflow")
      }
      // Derive before quantization: separately rounding both advance and
      // bottom introduces a false one-unit conflict at half coordinates.
      let derived_top = advance - height.to_double() - bottom
      if top_map != 0 &&
        @math.floor(top + 0.5) != @math.floor(derived_top + 0.5) {
        raise Invalid(
          "VVAR top and bottom bearings cannot both be represented in a static glyph",
        )
      }
      top = derived_top
    }
    if top < -32768.5 || top >= 32767.5 {
      raise Invalid("VVAR top bearing overflows signed 16-bit range")
    }
    set_u16(result, gid * 4, new_advance)
    set_i16(result, gid * 4 + 2, ot_round(top))
  }
  Some(Bytes::from_array(result[:]))
}
