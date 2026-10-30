///|
fn gdef_version(data : Bytes) -> Int32 raise FontError {
  let version = read_uint32(data, 0)
  if version != 0x00010000U && version != 0x00010002U && version != 0x00010003U {
    raise Unsupported("GDEF version must be 1.0, 1.2 or 1.3")
  }
  require_range(
    data,
    0,
    if version == 0x00010000U {
      12
    } else if version == 0x00010002U {
      14
    } else {
      18
    },
  )
  (version & 0xFFFFU).reinterpret_as_int()
}

///|
fn gdef_caret(ctx : LayoutContext, pos : Int32) -> LayoutBlock raise FontError {
  match read_u16(ctx.data, pos) {
    1 | 2 => layout_leaf(ctx, pos, 4)
    3 => {
      let device = layout_device(ctx, pos, pos + 4)
      let out = layout_block(if device.block is Some(_) { 6 } else { 4 })
      set_u16(out.data, 0, if device.block is Some(_) { 3 } else { 1 })
      set_i16(
        out.data,
        2,
        layout_metric(
          read_i16(ctx.data, pos + 2),
          device.delta,
          "ligature caret",
        ),
      )
      if device.block is Some(child) {
        layout_link(out, 4, child)
      }
      out
    }
    _ => raise Unsupported("GDEF CaretValue format")
  }
}

///|
fn gdef_caret_list(
  ctx : LayoutContext,
  pos : Int32,
) -> LayoutBlock raise FontError {
  let count = read_u16(ctx.data, pos + 2)
  layout_span(ctx, pos + 4, count, 2)
  let (coverage, covered) = layout_coverage(ctx, layout_required(ctx, pos, pos))
  if count != covered {
    raise Invalid("GDEF ligature coverage/count mismatch")
  }
  let out = layout_block(4 + count * 2)
  set_u16(out.data, 2, count)
  layout_link(out, 0, coverage)
  for i in 0..<count {
    let ligature = layout_required(ctx, pos, pos + 4 + i * 2)
    let carets = read_u16(ctx.data, ligature)
    layout_span(ctx, ligature + 2, carets, 2)
    let child = layout_block(2 + carets * 2)
    set_u16(child.data, 0, carets)
    for j in 0..<carets {
      layout_link(
        child,
        2 + j * 2,
        gdef_caret(ctx, layout_required(ctx, ligature, ligature + 2 + j * 2)),
      )
    }
    layout_link(out, 4 + i * 2, child)
  }
  out
}

///|
fn gdef_attach_list(
  ctx : LayoutContext,
  pos : Int32,
) -> LayoutBlock raise FontError {
  let count = read_u16(ctx.data, pos + 2)
  layout_span(ctx, pos + 4, count, 2)
  let (coverage, covered) = layout_coverage(ctx, layout_required(ctx, pos, pos))
  if count != covered {
    raise Invalid("GDEF attach coverage/count mismatch")
  }
  let out = layout_block(4 + count * 2)
  set_u16(out.data, 2, count)
  layout_link(out, 0, coverage)
  for i in 0..<count {
    let point = layout_required(ctx, pos, pos + 4 + i * 2)
    let n = read_u16(ctx.data, point)
    layout_span(ctx, point + 2, n, 2)
    let mut previous = -1
    for j in 0..<n {
      let value = read_u16(ctx.data, point + 2 + j * 2)
      if value <= previous {
        raise Invalid("GDEF attachment point indices are not sorted")
      }
      previous = value
    }
    layout_link(out, 4 + i * 2, layout_leaf(ctx, point, 2 + n * 2))
  }
  out
}

///|
fn gdef_marks(ctx : LayoutContext, pos : Int32) -> LayoutBlock raise FontError {
  if read_u16(ctx.data, pos) != 1 {
    raise Unsupported("GDEF MarkGlyphSets format")
  }
  let count = read_u16(ctx.data, pos + 2)
  layout_span(ctx, pos + 4, count, 4)
  let out = layout_block(4 + count * 4)
  set_u16(out.data, 0, 1)
  set_u16(out.data, 2, count)
  for i in 0..<count {
    let (coverage, _) = layout_coverage(
      ctx,
      layout_required(ctx, pos, pos + 4 + i * 4, wide=true),
    )
    layout_link(out, 4 + i * 4, coverage, wide=true)
  }
  out
}

///|
fn freeze_gdef(
  ctx : LayoutContext,
  version : Int32,
) -> LayoutBlock raise FontError {
  let has_marks = version >= 2 && read_u16(ctx.data, 12) != 0
  let out = layout_block(if has_marks { 14 } else { 12 })
  set_u32(out.data, 0, if has_marks { 0x00010002U } else { 0x00010000U })
  for field in [4, 6, 8, 10] {
    if layout_offset(ctx, 0, field) is Some(pos) {
      let child = match field {
        4 => layout_class_def(ctx, pos, class_limit=5)
        6 => gdef_attach_list(ctx, pos)
        8 => gdef_caret_list(ctx, pos)
        _ => layout_class_def(ctx, pos)
      }
      layout_link(out, field, child)
    }
  }
  if has_marks {
    layout_link(out, 12, gdef_marks(ctx, layout_required(ctx, 0, 12)))
  }
  out
}

///|
fn instantiate_layout(
  tables : Map[String, Bytes],
  coords : Array[Double],
  work_limit : Int32,
  max_bytes : Int32,
) -> LayoutAudit raise FontError {
  let originals = tables.copy()
  let data = tables.get("GDEF").unwrap_or(b"")
  let version = if data.is_empty() { 0 } else { gdef_version(data) }
  let store = if version == 3 && read_u32(data, 14) != 0 {
    let offset = read_u32(data, 14)
    if offset < 18 {
      raise Invalid("GDEF variation store overlaps its header")
    }
    Some(variation_store(data, offset, coords, work_limit~))
  } else {
    None
  }
  let ctx : LayoutContext = {
    data,
    glyphs: read_u16(table_required(tables, "maxp"), 4),
    store,
    work: Ref(0),
    limit: work_limit,
    deltas: Ref(0),
    lookup_types: [],
  }
  let block = if data.is_empty() {
    None
  } else {
    Some(freeze_gdef(ctx, version))
  }
  let gdef_indices = ctx.deltas.val
  let features : Array[(String, Bool, Int32?)] = []
  for tag in ["GSUB", "GPOS"] {
    if tables.get(tag) is Some(layout) {
      let present = read_uint32(layout, 0) == 0x00010001U &&
        read_u32(layout, 10) != 0
      let (output, selected) = freeze_feature_variations(
        { ..ctx, data: layout, },
        coords,
        max_bytes,
      )
      tables[tag] = output
      features.push((tag, present, selected))
    } else {
      features.push((tag, false, None))
    }
  }
  let before_gpos = ctx.deltas.val
  let gpos = if tables.get("GPOS") is Some(positioning) {
    let mark_sets = if version >= 2 && read_u16(data, 12) != 0 {
      read_u16(data, read_u16(data, 12) + 2)
    } else {
      0
    }
    Some(freeze_gpos({ ..ctx, data: positioning, }, mark_sets, max_bytes))
  } else {
    None
  }
  if store is Some(_) && block is Some(block) {
    tables["GDEF"] = serialize_layout(block, ctx, max_bytes)
  }
  if ctx.deltas.val != before_gpos && gpos is Some(output) {
    tables["GPOS"] = output
  }
  let rewritten : Array[String] = []
  for tag in ["GDEF", "GPOS", "GSUB"] {
    if originals.get(tag) != tables.get(tag) {
      rewritten.push(tag)
    }
  }
  {
    gdef_indices,
    gpos_indices: ctx.deltas.val - before_gpos,
    lookup_types: ctx.lookup_types,
    features,
    rewritten,
  }
}
