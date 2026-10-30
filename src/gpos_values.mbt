///|
priv struct LayoutValue {
  mask : Int32
  values : Array[Int32]
  devices : Array[LayoutBlock?]
}

///|
fn layout_value_size(format : Int32) -> Int32 raise FontError {
  if (format & 0xFF00) != 0 {
    raise Unsupported("reserved GPOS ValueFormat bits")
  }
  let mut size = 0
  for i in 0..<8 {
    if (format & (1 << i)) != 0 {
      size += 2
    }
  }
  size
}

///|
fn read_layout_value(
  ctx : LayoutContext,
  base : Int32,
  pos : Int32,
  format : Int32,
) -> LayoutValue raise FontError {
  let size = layout_value_size(format)
  require_range(ctx.data, pos, size)
  layout_charge(ctx, 1)
  let values = Array::make(4, 0)
  let devices : Array[LayoutBlock?] = Array::make(4, None)
  let mut cursor = pos
  let mut mask = format & 15
  for i in 0..<4 {
    if (format & (1 << i)) != 0 {
      values[i] = read_i16(ctx.data, cursor)
      cursor += 2
    }
  }
  for i in 0..<4 {
    if (format & (16 << i)) != 0 {
      let offset = read_u16(ctx.data, cursor)
      let device = layout_device(ctx, base, cursor)
      cursor += 2
      if device.block is Some(child) {
        devices[i] = Some(child)
        mask = mask | (16 << i)
      } else if offset != 0 {
        values[i] = layout_metric(values[i], device.delta, "GPOS value")
        mask = mask | (1 << i)
      }
    }
  }
  { mask, values, devices, }
}

///|
fn append_layout_value(
  block : LayoutBlock,
  value : LayoutValue,
  mask : Int32,
) -> Unit raise FontError {
  for i in 0..<4 {
    if (mask & (1 << i)) != 0 {
      push_i16(block.data, value.values[i])
    }
  }
  for i in 0..<4 {
    if (mask & (16 << i)) != 0 {
      let field = block.data.length()
      push_u16(block.data, 0)
      if value.devices[i] is Some(child) {
        layout_link(block, field, child)
      }
    }
  }
}

///|
fn gpos_single(ctx : LayoutContext, pos : Int32) -> LayoutBlock raise FontError {
  let format = read_u16(ctx.data, pos)
  if format != 1 && format != 2 {
    raise Unsupported("GPOS SinglePos format")
  }
  let old_mask = read_u16(ctx.data, pos + 4)
  let size = layout_value_size(old_mask)
  let (coverage, covered) = layout_coverage(
    ctx,
    layout_required(ctx, pos, pos + 2),
  )
  let count = if format == 1 { 1 } else { read_u16(ctx.data, pos + 6) }
  if format == 2 && count != covered {
    raise Invalid("SinglePos coverage/value count mismatch")
  }
  let start = pos + (if format == 1 { 6 } else { 8 })
  if size > 0 {
    layout_span(ctx, start, count, size)
  } else {
    layout_charge(ctx, count)
  }
  let values : Array[LayoutValue] = []
  let mut mask = 0
  for i in 0..<count {
    let value = read_layout_value(ctx, pos, start + i * size, old_mask)
    mask = mask | value.mask
    values.push(value)
  }
  let out = layout_block(if format == 1 { 6 } else { 8 })
  set_u16(out.data, 0, format)
  set_u16(out.data, 4, mask)
  if format == 2 {
    set_u16(out.data, 6, count)
  }
  for value in values {
    append_layout_value(out, value, mask)
  }
  layout_link(out, 2, coverage)
  out
}

///|
fn gpos_pair(ctx : LayoutContext, pos : Int32) -> LayoutBlock raise FontError {
  let format = read_u16(ctx.data, pos)
  if format != 1 && format != 2 {
    raise Unsupported("GPOS PairPos format")
  }
  let old1 = read_u16(ctx.data, pos + 4)
  let old2 = read_u16(ctx.data, pos + 6)
  let size1 = layout_value_size(old1)
  let size2 = layout_value_size(old2)
  let (coverage, covered) = layout_coverage(
    ctx,
    layout_required(ctx, pos, pos + 2),
  )
  let mut mask1 = 0
  let mut mask2 = 0
  if format == 1 {
    let count = read_u16(ctx.data, pos + 8)
    if count != covered {
      raise Invalid("PairPos coverage/set count mismatch")
    }
    layout_span(ctx, pos + 10, count, 2)
    let sets : Array[Array[(Int32, LayoutValue, LayoutValue)]] = []
    for i in 0..<count {
      let set = layout_required(ctx, pos, pos + 10 + i * 2)
      let pairs = read_u16(ctx.data, set)
      let stride = 2 + size1 + size2
      layout_span(ctx, set + 2, pairs, stride)
      let rows : Array[(Int32, LayoutValue, LayoutValue)] = []
      let mut previous = -1
      for j in 0..<pairs {
        let p = set + 2 + j * stride
        let glyph = read_u16(ctx.data, p)
        if glyph <= previous || glyph >= ctx.glyphs {
          raise Invalid("PairPos second glyphs are unsorted or out of range")
        }
        previous = glyph
        let value1 = read_layout_value(ctx, set, p + 2, old1)
        let value2 = read_layout_value(ctx, set, p + 2 + size1, old2)
        mask1 = mask1 | value1.mask
        mask2 = mask2 | value2.mask
        rows.push((glyph, value1, value2))
      }
      sets.push(rows)
    }
    let out = layout_block(10 + count * 2)
    set_u16(out.data, 0, 1)
    set_u16(out.data, 4, mask1)
    set_u16(out.data, 6, mask2)
    set_u16(out.data, 8, count)
    layout_link(out, 2, coverage)
    for i, rows in sets {
      let block = layout_block(2)
      set_u16(block.data, 0, rows.length())
      for (glyph, v1, v2) in rows {
        push_u16(block.data, glyph)
        append_layout_value(block, v1, mask1)
        append_layout_value(block, v2, mask2)
      }
      layout_link(out, 10 + i * 2, block)
    }
    out
  } else {
    let count1 = read_u16(ctx.data, pos + 12)
    let count2 = read_u16(ctx.data, pos + 14)
    if count1 == 0 || count2 == 0 {
      raise Invalid("PairPos class counts must be positive")
    }
    if count1 > ctx.limit / count2 {
      raise Limit("PairPos class matrix exceeds work budget")
    }
    let count = count1 * count2
    let stride = size1 + size2
    if stride > 0 {
      layout_span(ctx, pos + 16, count, stride)
    } else {
      layout_charge(ctx, count)
    }
    let class1 = layout_class_def(
      ctx,
      layout_required(ctx, pos, pos + 8),
      class_limit=count1,
    )
    let class2 = layout_class_def(
      ctx,
      layout_required(ctx, pos, pos + 10),
      class_limit=count2,
    )
    let rows : Array[(LayoutValue, LayoutValue)] = []
    for i in 0..<count {
      let p = pos + 16 + i * stride
      let v1 = read_layout_value(ctx, pos, p, old1)
      let v2 = read_layout_value(ctx, pos, p + size1, old2)
      mask1 = mask1 | v1.mask
      mask2 = mask2 | v2.mask
      rows.push((v1, v2))
    }
    let out = layout_block(16)
    set_u16(out.data, 0, 2)
    set_u16(out.data, 4, mask1)
    set_u16(out.data, 6, mask2)
    set_u16(out.data, 12, count1)
    set_u16(out.data, 14, count2)
    for (v1, v2) in rows {
      append_layout_value(out, v1, mask1)
      append_layout_value(out, v2, mask2)
    }
    layout_link(out, 2, coverage)
    layout_link(out, 8, class1)
    layout_link(out, 10, class2)
    out
  }
}

///|
fn gpos_subtable(
  ctx : LayoutContext,
  kind : Int32,
  pos : Int32,
  _lookups : Int32,
) -> LayoutBlock raise FontError {
  match kind {
    1 => gpos_single(ctx, pos)
    2 => gpos_pair(ctx, pos)
    _ =>
      raise Unsupported(
        "GPOS lookup type not yet supported: " + kind.to_string(),
      )
  }
}
