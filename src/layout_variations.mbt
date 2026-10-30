///|
fn layout_conditions(
  ctx : LayoutContext,
  pos : Int32?,
  coords : Array[Double],
) -> Bool raise FontError {
  guard pos is Some(pos) else { return true }
  let count = read_u16(ctx.data, pos)
  layout_span(ctx, pos + 2, count, 4)
  let mut matches = true
  for i in 0..<count {
    let condition = layout_required(ctx, pos, pos + 2 + i * 4, wide=true)
    if read_u16(ctx.data, condition) != 1 {
      raise Unsupported(
        "FeatureVariations condition format (only axis ranges are supported)",
      )
    }
    let axis = read_u16(ctx.data, condition + 2)
    let low = read_i16(ctx.data, condition + 4).to_double() / 16384.0
    let high = read_i16(ctx.data, condition + 6).to_double() / 16384.0
    if axis >= coords.length() || low < -1.0 || high > 1.0 || low > high {
      raise Invalid("FeatureVariations axis/range is invalid")
    }
    // Do not short circuit: unsupported data in an unmatched branch is refused.
    if coords[axis] < low || coords[axis] > high {
      matches = false
    }
  }
  matches
}

///|
fn freeze_feature_variations(
  ctx : LayoutContext,
  coords : Array[Double],
  max_bytes : Int32,
) -> (Bytes, Int32?) raise FontError {
  if ctx.data.length() > max_bytes {
    raise Limit("conditional layout input exceeds output byte budget")
  }
  let version = read_uint32(ctx.data, 0)
  if version == 0x00010000U {
    return (ctx.data, None)
  }
  if version != 0x00010001U {
    raise Unsupported("layout table version")
  }
  guard layout_offset(ctx, 0, 10, wide=true) is Some(variations) else {
    return (ctx.data, None)
  }
  if read_uint32(ctx.data, variations) != 0x00010000U {
    raise Unsupported("FeatureVariations version")
  }
  let count = read_u32(ctx.data, variations + 4)
  layout_span(ctx, variations + 8, count, 8)
  let feature_pos = layout_required(ctx, 0, 6)
  let feature_count = read_u16(ctx.data, feature_pos)
  let lookup_pos = layout_required(ctx, 0, 8)
  let lookups = read_u16(ctx.data, lookup_pos)
  ignore(layout_scripts(ctx, layout_required(ctx, 0, 4), feature_count))
  let features = layout_features(ctx, feature_pos, lookups)
  let mut selected : Int32? = None
  let mut replacements : Array[(Int32, LayoutBlock)] = []
  for i in 0..<count {
    let record = variations + 8 + i * 8
    let matches = layout_conditions(
      ctx,
      layout_offset(ctx, variations, record, wide=true),
      coords,
    )
    let rows : Array[(Int32, LayoutBlock)] = []
    if layout_offset(ctx, variations, record + 4, wide=true)
      is Some(substitution) {
      if read_uint32(ctx.data, substitution) != 0x00010000U {
        raise Unsupported("FeatureTableSubstitution version")
      }
      let n = read_u16(ctx.data, substitution + 4)
      layout_span(ctx, substitution + 6, n, 6)
      let mut previous = -1
      for j in 0..<n {
        let p = substitution + 6 + j * 6
        let index = read_u16(ctx.data, p)
        if index <= previous || index >= feature_count {
          raise Invalid(
            "FeatureVariations substitution indices are unsorted, repeated or out of range",
          )
        }
        previous = index
        let tag = read_tag(ctx.data, feature_pos + 2 + index * 6)
        rows.push(
          (
            index,
            layout_feature(
              ctx,
              layout_required(ctx, substitution, p + 2, wide=true),
              tag,
              lookups,
            ),
          ),
        )
      }
    }
    if matches && selected is None {
      selected = Some(i)
      replacements = rows
    }
  }
  for (index, replacement) in replacements {
    // layout_features emits exactly one link in original feature-index order.
    features.links[index] = (6 + index * 6, 2, replacement)
  }
  if replacements.is_empty() {
    layout_charge(ctx, ctx.data.length() / 2 + 1)
    let data = byte_array(ctx.data)
    set_u32(data, 0, 0x00010000U)
    set_u32(data, 10, 0U)
    return (Bytes::from_array(data[:]), selected)
  }
  // Relocate the new FeatureList before the complete original table. The old
  // lookup/script graph keeps all relative offsets, payloads and lookup IDs.
  let feature_bytes = serialize_layout(features, ctx, max_bytes)
  let base = 10 + feature_bytes.length()
  if base > max_bytes || ctx.data.length() > max_bytes - base {
    raise Limit("conditional layout output exceeds byte budget")
  }
  let out = layout_block(10)
  layout_charge(ctx, ctx.data.length() / 2 + 1)
  set_u32(out.data, 0, 0x00010000U)
  set_u16(out.data, 4, base + read_u16(ctx.data, 4))
  set_u16(out.data, 6, 10)
  set_u16(out.data, 8, base + lookup_pos)
  for byte in feature_bytes {
    out.data.push(byte)
  }
  for byte in ctx.data {
    out.data.push(byte)
  }
  (Bytes::from_array(out.data[:]), selected)
}
