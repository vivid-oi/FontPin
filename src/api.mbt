///|
/// Read a variable TrueType font, checking table and whole-font checksums.
pub fn Font::parse(
  data : Bytes,
  max_bytes~ : Int32 = 32 * 1024 * 1024,
) -> Font raise FontError {
  let tables = parse_sfnt(data, max_bytes)
  let design_axes = parse_axes(tables)
  ignore(table_required(tables, "gvar"))
  { tables, design_axes, }
}

///|
/// Inspect either a static or variable TrueType font.
pub fn inspect_font(
  data : Bytes,
  max_bytes~ : Int32 = 32 * 1024 * 1024,
) -> Json raise FontError {
  let tables = parse_sfnt(data, max_bytes)
  let axes = if tables.contains("fvar") { parse_axes(tables) } else { [] }
  let tags = tables.keys().to_array()
  tags.sort_by((a, b) => a.lexical_compare(b))
  {
    "axes": Json(axes),
    "tables": Json(tags),
    "glyph_count": Json(read_u16(tables["maxp"], 4)),
    "bytes": Json(data.length()),
  }
}

///|
fn preflight(tables : Map[String, Bytes]) -> Unit raise FontError {
  let allowed = [
    "head", "hhea", "maxp", "OS/2", "hmtx", "cmap", "loca", "glyf", "name", "post",
    "gasp", "cvt ", "fpgm", "prep", "kern", "GSUB", "GPOS", "GDEF", "STAT", "fvar",
    "avar", "gvar", "HVAR", "MVAR", "cvar", "vhea", "vmtx", "ltag", "VVAR",
  ]
  for tag, _ in tables {
    if !allowed.contains(tag) {
      raise Unsupported("table cannot yet be safely instantiated: " + tag)
    }
  }
  for tag in ["fpgm", "prep"] {
    if tables.get(tag) is Some(program) {
      guard_static_hints(program, tag)
    }
  }
  if tables.get("GDEF") is Some(data) {
    ignore(gdef_version(data))
  }
  for tag in ["GSUB", "GPOS"] {
    if tables.get(tag) is Some(data) {
      let version = read_uint32(data, 0)
      if version != 0x00010000U && version != 0x00010001U {
        raise Unsupported(tag + " version")
      }
      require_range(data, 0, if version == 0x00010001U { 14 } else { 10 })
    }
  }
}

///|
/// Pin all axes. Missing coordinates use defaults; invalid coordinates fail.
pub fn Font::instantiate(
  self : Font,
  coordinates : Map[String, Double],
  max_bytes~ : Int32 = 32 * 1024 * 1024,
  work_limit~ : Int32 = 20_000_000,
) -> Instance raise FontError {
  if max_bytes < 1024 || max_bytes > 128 * 1024 * 1024 {
    raise Limit("max_bytes must be 1024..134217728")
  }
  if work_limit < 1 || work_limit > 100_000_000 {
    raise Limit("work_limit must be 1..100000000")
  }
  preflight(self.tables)
  let (coords, actual) = normalized_coordinates(self, coordinates)
  let glyphs = instantiate_glyphs(self.tables, coords, work_limit)
  let hmtx = apply_hvar(
    self.tables,
    coords,
    glyphs.hmtx,
    work_limit~,
    outlines=Some(glyphs),
  )
  let tables = self.tables.copy()
  let layout = instantiate_layout(tables, coords, work_limit, max_bytes)
  tables["glyf"] = glyphs.glyf
  tables["loca"] = glyphs.loca
  tables["hmtx"] = hmtx
  if apply_vvar(self.tables, coords, glyphs, work_limit) is Some(metrics) {
    update_vertical_header(tables, glyphs, metrics)
  }
  let head = byte_array(tables["head"])
  set_i16(head, 50, 1)
  set_i16(head, 36, glyphs.x_min)
  set_i16(head, 38, glyphs.y_min)
  set_i16(head, 40, glyphs.x_max)
  set_i16(head, 42, glyphs.y_max)
  set_u16(head, 16, read_u16(tables["head"], 16) & 0xFFFD)
  tables["head"] = Bytes::from_array(head[:])
  let hhea = byte_array(tables["hhea"])
  set_u16(hhea, 34, glyphs.glyph_count)
  // Recompute aggregate horizontal fields from FINAL HVAR-adjusted metrics.
  let mut advance_max = 0
  let mut min_lsb = 32767
  let mut min_rsb = 32767
  let mut max_extent = -32768
  for gid in 0..<glyphs.glyph_count {
    let advance = read_u16(hmtx, gid * 4)
    let lsb = read_i16(hmtx, gid * 4 + 2)
    let p = read_u32(glyphs.loca, gid * 4)
    let end = read_u32(glyphs.loca, gid * 4 + 4)
    if advance > advance_max {
      advance_max = advance
    }
    if p < end {
      let width = read_i16(glyphs.glyf, p + 6) - read_i16(glyphs.glyf, p + 2)
      min_lsb = @cmp.minimum(min_lsb, lsb)
      min_rsb = @cmp.minimum(min_rsb, advance - lsb - width)
      max_extent = @cmp.maximum(max_extent, lsb + width)
    }
  }
  if min_lsb == 32767 && max_extent == -32768 {
    min_lsb = 0
    min_rsb = 0
    max_extent = 0
  }
  set_u16(hhea, 10, advance_max)
  set_i16(hhea, 12, min_lsb)
  set_i16(hhea, 14, min_rsb)
  set_i16(hhea, 16, max_extent)
  tables["hhea"] = Bytes::from_array(hhea[:])
  // Modern OS/2 recommendation: average all positive advances after HVAR.
  let mut width_sum = 0L
  let mut width_count = 0
  for gid in 0..<glyphs.glyph_count {
    let width = read_u16(hmtx, gid * 4)
    if width > 0 {
      width_sum += width.to_int64()
      width_count += 1
    }
  }
  let os2 = byte_array(tables["OS/2"])
  set_i16(
    os2,
    2,
    if width_count == 0 {
      0
    } else {
      ot_round(width_sum.to_double() / width_count.to_double())
    },
  )
  tables["OS/2"] = Bytes::from_array(os2[:])
  update_instance_names(tables, actual)
  apply_mvar(tables, coords, work_limit~)
  apply_cvar(tables, coords, work_limit~)
  update_stat(tables, actual)
  for tag in ["fvar", "avar", "gvar", "HVAR", "MVAR", "cvar", "VVAR"] {
    tables.remove(tag)
  }
  let data = build_sfnt(tables, max_bytes)
  ignore(parse_sfnt(data, max_bytes))
  { data, coordinates: actual, glyph_count: glyphs.glyph_count, layout, }
}
