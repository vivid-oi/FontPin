///|
fn layout_anchor(
  ctx : LayoutContext,
  pos : Int32,
) -> LayoutBlock raise FontError {
  let format = read_u16(ctx.data, pos)
  match format {
    1 => layout_leaf(ctx, pos, 6)
    2 => layout_leaf(ctx, pos, 8)
    3 => {
      let x = layout_device(ctx, pos, pos + 6)
      let y = layout_device(ctx, pos, pos + 8)
      let has_device = x.block is Some(_) || y.block is Some(_)
      let out = layout_block(if has_device { 10 } else { 6 })
      set_u16(out.data, 0, if has_device { 3 } else { 1 })
      set_i16(
        out.data,
        2,
        layout_metric(read_i16(ctx.data, pos + 2), x.delta, "anchor X"),
      )
      set_i16(
        out.data,
        4,
        layout_metric(read_i16(ctx.data, pos + 4), y.delta, "anchor Y"),
      )
      if x.block is Some(block) {
        layout_link(out, 6, block)
      }
      if y.block is Some(block) {
        layout_link(out, 8, block)
      }
      out
    }
    _ => raise Unsupported("GPOS Anchor format")
  }
}

///|
fn layout_anchor_link(
  ctx : LayoutContext,
  out : LayoutBlock,
  field : Int32,
  base : Int32,
  source_field : Int32,
) -> Unit raise FontError {
  if layout_offset(ctx, base, source_field) is Some(pos) {
    layout_link(out, field, layout_anchor(ctx, pos))
  }
}

///|
fn gpos_cursive(
  ctx : LayoutContext,
  pos : Int32,
) -> LayoutBlock raise FontError {
  if read_u16(ctx.data, pos) != 1 {
    raise Unsupported("CursivePos format")
  }
  let (coverage, covered) = layout_coverage(
    ctx,
    layout_required(ctx, pos, pos + 2),
  )
  let count = read_u16(ctx.data, pos + 4)
  if count != covered {
    raise Invalid("CursivePos coverage/count mismatch")
  }
  layout_span(ctx, pos + 6, count, 4)
  let out = layout_block(6 + count * 4)
  set_u16(out.data, 0, 1)
  set_u16(out.data, 4, count)
  layout_link(out, 2, coverage)
  for i in 0..<(count * 2) {
    layout_anchor_link(ctx, out, 6 + i * 2, pos, pos + 6 + i * 2)
  }
  out
}

///|
fn gpos_mark_array(
  ctx : LayoutContext,
  pos : Int32,
  covered : Int32,
  classes : Int32,
) -> LayoutBlock raise FontError {
  let count = read_u16(ctx.data, pos)
  if count != covered {
    raise Invalid("MarkArray coverage/count mismatch")
  }
  layout_span(ctx, pos + 2, count, 4)
  let out = layout_block(2 + count * 4)
  set_u16(out.data, 0, count)
  for i in 0..<count {
    let class_id = read_u16(ctx.data, pos + 2 + i * 4)
    if class_id >= classes {
      raise Invalid("MarkArray class out of range")
    }
    set_u16(out.data, 2 + i * 4, class_id)
    layout_link(
      out,
      4 + i * 4,
      layout_anchor(ctx, layout_required(ctx, pos, pos + 4 + i * 4)),
    )
  }
  out
}

///|
fn gpos_anchor_matrix(
  ctx : LayoutContext,
  pos : Int32,
  count : Int32,
  classes : Int32,
) -> LayoutBlock raise FontError {
  if classes <= 0 || count > ctx.limit / classes {
    raise Limit("anchor matrix exceeds work budget")
  }
  let cells = count * classes
  layout_span(ctx, pos + 2, cells, 2)
  let out = layout_block(2 + cells * 2)
  set_u16(out.data, 0, count)
  for i in 0..<cells {
    layout_anchor_link(ctx, out, 2 + i * 2, pos, pos + 2 + i * 2)
  }
  out
}

///|
fn gpos_marks(
  ctx : LayoutContext,
  pos : Int32,
  kind : Int32,
) -> LayoutBlock raise FontError {
  if read_u16(ctx.data, pos) != 1 {
    raise Unsupported("mark positioning format")
  }
  let (mark_cov, marks) = layout_coverage(
    ctx,
    layout_required(ctx, pos, pos + 2),
  )
  let (base_cov, bases) = layout_coverage(
    ctx,
    layout_required(ctx, pos, pos + 4),
  )
  let classes = read_u16(ctx.data, pos + 6)
  if classes == 0 {
    raise Invalid("mark class count must be positive")
  }
  let out = layout_block(12)
  set_u16(out.data, 0, 1)
  set_u16(out.data, 6, classes)
  layout_link(out, 2, mark_cov)
  layout_link(out, 4, base_cov)
  layout_link(
    out,
    8,
    gpos_mark_array(ctx, layout_required(ctx, pos, pos + 8), marks, classes),
  )
  let base = layout_required(ctx, pos, pos + 10)
  if read_u16(ctx.data, base) != bases {
    raise Invalid("base/ligature/mark2 coverage/count mismatch")
  }
  let array = if kind == 5 {
    layout_span(ctx, base + 2, bases, 2)
    let array = layout_block(2 + bases * 2)
    set_u16(array.data, 0, bases)
    for i in 0..<bases {
      let attach = layout_required(ctx, base, base + 2 + i * 2)
      let components = read_u16(ctx.data, attach)
      if components == 0 {
        raise Invalid("ligature attachment has no components")
      }
      layout_link(
        array,
        2 + i * 2,
        gpos_anchor_matrix(ctx, attach, components, classes),
      )
    }
    array
  } else {
    gpos_anchor_matrix(ctx, base, bases, classes)
  }
  layout_link(out, 10, array)
  out
}
