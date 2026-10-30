///|
priv struct LayoutBlock {
  data : Array[Byte]
  links : Array[(Int32, Int32, LayoutBlock)]
}

///|
priv struct LayoutContext {
  data : Bytes
  glyphs : Int32
  store : VariationStore?
  work : Ref[Int32]
  limit : Int32
  deltas : Ref[Int32]
  lookup_types : Array[Int32]
}

///|
fn layout_charge(ctx : LayoutContext, count : Int32) -> Unit raise FontError {
  if count < 0 || count > ctx.limit - ctx.work.val {
    raise Limit("layout work budget exceeded")
  }
  ctx.work.val += count
}

///|
fn layout_span(
  ctx : LayoutContext,
  pos : Int32,
  count : Int32,
  width : Int32,
) -> Unit raise FontError {
  iv_span(ctx.data, pos, count, width)
  layout_charge(ctx, count + 1)
}

///|
fn layout_block(size : Int32) -> LayoutBlock {
  { data: Array::make(size, 0), links: [], }
}

///|
fn layout_leaf(
  ctx : LayoutContext,
  pos : Int32,
  size : Int32,
) -> LayoutBlock raise FontError {
  require_range(ctx.data, pos, size)
  layout_charge(ctx, size / 2 + 1)
  { data: byte_array(ctx.data[pos:pos + size].to_owned()), links: [], }
}

///|
fn layout_offset(
  ctx : LayoutContext,
  base : Int32,
  field : Int32,
  wide~ : Bool = false,
) -> Int32? raise FontError {
  let offset = if wide {
    read_u32(ctx.data, field)
  } else {
    read_u16(ctx.data, field)
  }
  if offset == 0 {
    return None
  }
  require_range(ctx.data, base, 0)
  if offset > ctx.data.length() - base {
    raise Invalid("layout offset exceeds its table")
  }
  Some(base + offset)
}

///|
fn layout_required(
  ctx : LayoutContext,
  base : Int32,
  field : Int32,
  wide~ : Bool = false,
) -> Int32 raise FontError {
  guard layout_offset(ctx, base, field, wide~) is Some(pos) else {
    raise Invalid("required layout offset is zero")
  }
  pos
}

///|
fn layout_link(
  block : LayoutBlock,
  field : Int32,
  child : LayoutBlock,
  wide~ : Bool = false,
) -> Unit {
  block.links.push((field, if wide { 4 } else { 2 }, child))
}

///|
fn emit_layout(
  block : LayoutBlock,
  out : Array[Byte],
  ctx : LayoutContext,
  max_bytes : Int32,
  depth : Int32,
) -> Int32 raise FontError {
  if depth > 32 {
    raise Limit("layout serialization depth exceeds 32")
  }
  if block.data.length() > max_bytes - out.length() {
    raise Limit("instanced layout exceeds output budget")
  }
  layout_charge(ctx, block.data.length() / 2 + 1)
  let start = out.length()
  for byte in block.data {
    out.push(byte)
  }
  for (field, width, child) in block.links {
    if field < 0 || field > block.data.length() - width {
      raise Invalid("invalid layout relocation field")
    }
    let target = emit_layout(child, out, ctx, max_bytes, depth + 1)
    let offset = target - start
    if width == 2 {
      if offset > 65535 {
        raise Limit("layout offset exceeds unsigned 16-bit range")
      }
      set_u16(out, start + field, offset)
    } else {
      set_u32(out, start + field, offset.reinterpret_as_uint())
    }
  }
  start
}

///|
fn serialize_layout(
  block : LayoutBlock,
  ctx : LayoutContext,
  max_bytes : Int32,
) -> Bytes raise FontError {
  let out : Array[Byte] = []
  ignore(emit_layout(block, out, ctx, max_bytes, 0))
  Bytes::from_array(out[:])
}

///|
fn layout_coverage(
  ctx : LayoutContext,
  pos : Int32,
) -> (LayoutBlock, Int32) raise FontError {
  let format = read_u16(ctx.data, pos)
  let count = read_u16(ctx.data, pos + 2)
  let mut previous = -1
  let mut covered = 0
  if format == 1 {
    layout_span(ctx, pos + 4, count, 2)
    for i in 0..<count {
      let glyph = read_u16(ctx.data, pos + 4 + i * 2)
      if glyph <= previous || glyph >= ctx.glyphs {
        raise Invalid("unsorted or out-of-range layout coverage glyph")
      }
      previous = glyph
    }
    covered = count
  } else if format == 2 {
    layout_span(ctx, pos + 4, count, 6)
    for i in 0..<count {
      let p = pos + 4 + i * 6
      let start = read_u16(ctx.data, p)
      let end = read_u16(ctx.data, p + 2)
      if start <= previous ||
        start > end ||
        end >= ctx.glyphs ||
        read_u16(ctx.data, p + 4) != covered {
        raise Invalid("invalid layout coverage range or index")
      }
      covered += end - start + 1
      previous = end
    }
  } else {
    raise Unsupported("layout Coverage format")
  }
  (
    layout_leaf(ctx, pos, 4 + count * (if format == 1 { 2 } else { 6 })),
    covered,
  )
}

///|
fn layout_class_def(
  ctx : LayoutContext,
  pos : Int32,
  class_limit~ : Int32 = 65536,
) -> LayoutBlock raise FontError {
  let format = read_u16(ctx.data, pos)
  if format == 1 {
    let first = read_u16(ctx.data, pos + 2)
    let count = read_u16(ctx.data, pos + 4)
    layout_span(ctx, pos + 6, count, 2)
    if first + count > ctx.glyphs {
      raise Invalid("layout ClassDef glyph range exceeds maxp")
    }
    for i in 0..<count {
      if read_u16(ctx.data, pos + 6 + i * 2) >= class_limit {
        raise Invalid("layout class exceeds declared class count")
      }
    }
    layout_leaf(ctx, pos, 6 + count * 2)
  } else if format == 2 {
    let count = read_u16(ctx.data, pos + 2)
    layout_span(ctx, pos + 4, count, 6)
    let mut previous = -1
    for i in 0..<count {
      let p = pos + 4 + i * 6
      let start = read_u16(ctx.data, p)
      let end = read_u16(ctx.data, p + 2)
      if start <= previous ||
        start > end ||
        end >= ctx.glyphs ||
        read_u16(ctx.data, p + 4) >= class_limit {
        raise Invalid("invalid layout class range")
      }
      previous = end
    }
    layout_leaf(ctx, pos, 4 + count * 6)
  } else {
    raise Unsupported("layout ClassDef format")
  }
}

///|
priv struct LayoutDevice {
  delta : Double
  block : LayoutBlock?
}

///|
fn layout_device(
  ctx : LayoutContext,
  base : Int32,
  field : Int32,
) -> LayoutDevice raise FontError {
  guard layout_offset(ctx, base, field) is Some(pos) else {
    return { delta: 0.0, block: None, }
  }
  layout_charge(ctx, 1)
  let first = read_u16(ctx.data, pos)
  let last = read_u16(ctx.data, pos + 2)
  let format = read_u16(ctx.data, pos + 4)
  if format == 0x8000 {
    guard ctx.store is Some(store) else {
      raise Invalid("layout VariationIndex requires GDEF item variation store")
    }
    layout_charge(ctx, variation_work(store, first, last))
    ctx.deltas.val += 1
    { delta: variation_delta(store, first, last), block: None, }
  } else {
    if format < 1 || format > 3 {
      raise Unsupported("layout Device delta format")
    }
    if first > last {
      raise Invalid("layout Device ppem range is reversed")
    }
    let bits = 1 << format
    let words = ((last - first + 1) * bits + 15) / 16
    { delta: 0.0, block: Some(layout_leaf(ctx, pos, 6 + words * 2)), }
  }
}

///|
fn layout_metric(
  base : Int32,
  delta : Double,
  context : String,
) -> Int32 raise FontError {
  let value = base.to_double() + delta
  if value.is_nan() || value < -32768.5 || value >= 32767.5 {
    raise Invalid("layout signed 16-bit overflow: " + context)
  }
  ot_round(value)
}
