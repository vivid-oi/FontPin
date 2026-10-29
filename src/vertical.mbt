///|
// OpenType vhea/vmtx: vertical phantom points are (0,yMax+tsb) and
// (0,yMax+tsb-advanceHeight). Keep the origin unrounded until final bounds.
// https://learn.microsoft.com/en-us/typography/opentype/spec/vhea
fn vertical_metrics(
  tables : Map[String, Bytes],
  glyph_count : Int32,
) -> (Bytes, Int32)? raise FontError {
  match (tables.get("vhea"), tables.get("vmtx")) {
    (None, None) => None
    (Some(header), Some(metrics)) => {
      if header.length() != 36 {
        raise Invalid("vhea length must be 36 bytes")
      }
      let version = read_uint32(header, 0)
      if version != 0x00010000U && version != 0x00011000U {
        raise Unsupported("vhea version must be 1.0 or 1.1")
      }
      for offset in [24, 26, 28, 30, 32] {
        if read_u16(header, offset) != 0 {
          raise Invalid(
            "vhea reserved fields and metricDataFormat must be zero",
          )
        }
      }
      let count = read_u16(header, 34)
      if count < 1 || count > glyph_count {
        raise Invalid("invalid vertical metric count")
      }
      if metrics.length() != count * 4 + (glyph_count - count) * 2 {
        raise Invalid("vmtx length does not match glyph and metric counts")
      }
      Some((metrics, count))
    }
    _ => raise Invalid("vhea and vmtx must occur together")
  }
}

///|
fn update_vertical_header(
  tables : Map[String, Bytes],
  glyphs : GlyphResult,
  metrics : Bytes,
) -> Unit raise FontError {
  let header = byte_array(table_required(tables, "vhea"))
  let mut advance_max = 0
  let mut min_tsb = 32767
  let mut min_bsb = 32767
  let mut max_extent = -32768
  for gid in 0..<glyphs.glyph_count {
    let advance = read_u16(metrics, gid * 4)
    let tsb = read_i16(metrics, gid * 4 + 2)
    advance_max = @cmp.maximum(advance_max, advance)
    let start = read_u32(glyphs.loca, gid * 4)
    let end = read_u32(glyphs.loca, gid * 4 + 4)
    // Zero-contour glyphs have no outline even when they contain instructions.
    if start < end && read_i16(glyphs.glyf, start) != 0 {
      let height = read_i16(glyphs.glyf, start + 8) -
        read_i16(glyphs.glyf, start + 4)
      min_tsb = @cmp.minimum(min_tsb, tsb)
      min_bsb = @cmp.minimum(min_bsb, advance - tsb - height)
      max_extent = @cmp.maximum(max_extent, tsb + height)
    }
  }
  if min_tsb == 32767 && max_extent == -32768 {
    min_tsb = 0
    min_bsb = 0
    max_extent = 0
  }
  set_u16(header, 10, advance_max)
  set_i16(header, 12, min_tsb)
  set_i16(header, 14, min_bsb)
  set_i16(header, 16, max_extent)
  set_u16(header, 34, glyphs.glyph_count)
  tables["vhea"] = Bytes::from_array(header[:])
  tables["vmtx"] = metrics
}
