///|
fn layout_actions(
  ctx : LayoutContext,
  pos : Int32,
  count : Int32,
  inputs : Int32,
  lookups : Int32,
) -> Unit raise FontError {
  layout_span(ctx, pos, count, 4)
  for i in 0..<count {
    if read_u16(ctx.data, pos + i * 4) >= inputs ||
      read_u16(ctx.data, pos + i * 4 + 2) >= lookups {
      raise Invalid("context sequence/lookup index out of range")
    }
  }
}

///|
fn layout_sequence(
  ctx : LayoutContext,
  pos : Int32,
  count : Int32,
  bound : Int32,
) -> Unit raise FontError {
  layout_span(ctx, pos, count, 2)
  for i in 0..<count {
    if read_u16(ctx.data, pos + i * 2) >= bound {
      raise Invalid("context glyph/class out of range")
    }
  }
}

///|
fn gpos_context_rule(
  ctx : LayoutContext,
  pos : Int32,
  chained : Bool,
  bounds : Array[Int32],
  lookups : Int32,
) -> LayoutBlock raise FontError {
  let mut cursor = pos
  if chained {
    let n = read_u16(ctx.data, cursor)
    layout_sequence(ctx, cursor + 2, n, bounds[0])
    cursor += 2 + n * 2
  }
  let inputs = read_u16(ctx.data, cursor)
  if inputs == 0 {
    raise Invalid("context input sequence is empty")
  }
  let mut count = 0
  if chained {
    layout_sequence(ctx, cursor + 2, inputs - 1, bounds[1])
    cursor += 2 + (inputs - 1) * 2
    let n = read_u16(ctx.data, cursor)
    layout_sequence(ctx, cursor + 2, n, bounds[2])
    cursor += 2 + n * 2
    count = read_u16(ctx.data, cursor)
    cursor += 2
  } else {
    count = read_u16(ctx.data, cursor + 2)
    layout_sequence(ctx, cursor + 4, inputs - 1, bounds[1])
    cursor += 4 + (inputs - 1) * 2
  }
  layout_actions(ctx, cursor, count, inputs, lookups)
  layout_leaf(ctx, pos, cursor + count * 4 - pos)
}

///|
fn gpos_context(
  ctx : LayoutContext,
  pos : Int32,
  chained : Bool,
  lookups : Int32,
) -> LayoutBlock raise FontError {
  let format = read_u16(ctx.data, pos)
  if format < 1 || format > 3 {
    raise Unsupported("context positioning format")
  }
  if format == 3 {
    let mut cursor = pos + 2
    let coverages : Array[(Int32, LayoutBlock)] = []
    let mut inputs = 0
    let mut count = 0
    if !chained {
      inputs = read_u16(ctx.data, cursor)
      count = read_u16(ctx.data, cursor + 2)
      cursor += 4
      layout_span(ctx, cursor, inputs, 2)
      for i in 0..<inputs {
        let p = cursor + i * 2
        let (cov, _) = layout_coverage(ctx, layout_required(ctx, pos, p))
        coverages.push((p - pos, cov))
      }
      cursor += inputs * 2
    } else {
      for part in 0..<3 {
        let n = read_u16(ctx.data, cursor)
        if part == 1 {
          inputs = n
        }
        cursor += 2
        layout_span(ctx, cursor, n, 2)
        for i in 0..<n {
          let p = cursor + i * 2
          let (cov, _) = layout_coverage(ctx, layout_required(ctx, pos, p))
          coverages.push((p - pos, cov))
        }
        cursor += n * 2
      }
      count = read_u16(ctx.data, cursor)
      cursor += 2
    }
    if inputs == 0 {
      raise Invalid("context input coverage sequence is empty")
    }
    layout_actions(ctx, cursor, count, inputs, lookups)
    let out = layout_leaf(ctx, pos, cursor + count * 4 - pos)
    for (field, cov) in coverages {
      layout_link(out, field, cov)
    }
    return out
  }
  let (coverage, covered) = layout_coverage(
    ctx,
    layout_required(ctx, pos, pos + 2),
  )
  let count_field = if format == 1 { 4 } else if chained { 10 } else { 6 }
  let count = read_u16(ctx.data, pos + count_field)
  if format == 1 && count != covered {
    raise Invalid("context coverage/rule-set count mismatch")
  }
  layout_span(ctx, pos + count_field + 2, count, 2)
  let out = layout_leaf(ctx, pos, count_field + 2 + count * 2)
  layout_link(out, 2, coverage)
  let bounds = if format == 1 {
    [ctx.glyphs, ctx.glyphs, ctx.glyphs]
  } else {
    [65536, count, 65536]
  }
  if format == 2 {
    if count == 0 {
      raise Invalid("context class-set count is zero")
    }
    for i in 0..<(if chained { 3 } else { 1 }) {
      let field = 4 + i * 2
      let bound = if !chained || i == 1 { count } else { 65536 }
      layout_link(
        out,
        field,
        layout_class_def(
          ctx,
          layout_required(ctx, pos, pos + field),
          class_limit=bound,
        ),
      )
    }
  }
  for i in 0..<count {
    let field = count_field + 2 + i * 2
    if layout_offset(ctx, pos, pos + field) is Some(set_pos) {
      let rules = read_u16(ctx.data, set_pos)
      layout_span(ctx, set_pos + 2, rules, 2)
      let set = layout_block(2 + rules * 2)
      set_u16(set.data, 0, rules)
      for j in 0..<rules {
        layout_link(
          set,
          2 + j * 2,
          gpos_context_rule(
            ctx,
            layout_required(ctx, set_pos, set_pos + 2 + j * 2),
            chained,
            bounds,
            lookups,
          ),
        )
      }
      layout_link(out, field, set)
    }
  }
  out
}
