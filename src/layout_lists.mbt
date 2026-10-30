///|
fn layout_langsys(
  ctx : LayoutContext,
  pos : Int32,
  features : Int32,
) -> LayoutBlock raise FontError {
  if read_u16(ctx.data, pos) != 0 {
    raise Unsupported("nonzero LangSys lookupOrder offset")
  }
  let required = read_u16(ctx.data, pos + 2)
  let count = read_u16(ctx.data, pos + 4)
  layout_span(ctx, pos + 6, count, 2)
  if required != 65535 && required >= features {
    raise Invalid("LangSys required feature index out of range")
  }
  for i in 0..<count {
    if read_u16(ctx.data, pos + 6 + i * 2) >= features {
      raise Invalid("LangSys feature index out of range")
    }
  }
  layout_leaf(ctx, pos, 6 + count * 2)
}

///|
fn layout_scripts(
  ctx : LayoutContext,
  pos : Int32,
  features : Int32,
) -> LayoutBlock raise FontError {
  let count = read_u16(ctx.data, pos)
  layout_span(ctx, pos + 2, count, 6)
  let out = layout_block(2 + count * 6)
  set_u16(out.data, 0, count)
  for i in 0..<count {
    let p = pos + 2 + i * 6
    ignore(read_tag(ctx.data, p))
    for j in 0..<4 {
      out.data[2 + i * 6 + j] = ctx.data[p + j]
    }
    let script_pos = layout_required(ctx, pos, p + 4)
    let languages = read_u16(ctx.data, script_pos + 2)
    layout_span(ctx, script_pos + 4, languages, 6)
    let script = layout_block(4 + languages * 6)
    set_u16(script.data, 2, languages)
    if layout_offset(ctx, script_pos, script_pos) is Some(default_pos) {
      layout_link(script, 0, layout_langsys(ctx, default_pos, features))
    }
    for k in 0..<languages {
      let lang = script_pos + 4 + k * 6
      ignore(read_tag(ctx.data, lang))
      for j in 0..<4 {
        script.data[4 + k * 6 + j] = ctx.data[lang + j]
      }
      layout_link(
        script,
        8 + k * 6,
        layout_langsys(
          ctx,
          layout_required(ctx, script_pos, lang + 4),
          features,
        ),
      )
    }
    layout_link(out, 6 + i * 6, script)
  }
  out
}

///|
fn layout_feature(
  ctx : LayoutContext,
  pos : Int32,
  tag : String,
  lookups : Int32,
) -> LayoutBlock raise FontError {
  let count = read_u16(ctx.data, pos + 2)
  layout_span(ctx, pos + 4, count, 2)
  let out = layout_leaf(ctx, pos, 4 + count * 2)
  set_u16(out.data, 0, 0)
  for i in 0..<count {
    if read_u16(ctx.data, pos + 4 + i * 2) >= lookups {
      raise Invalid("feature lookup index out of range")
    }
  }
  if layout_offset(ctx, pos, pos) is Some(parameters) {
    let size = if tag == "size" {
      10
    } else if tag.length() == 4 &&
      tag.has_prefix("ss") &&
      tag[2].to_int() >= 48 &&
      tag[2].to_int() <= 57 &&
      tag[3].to_int() >= 48 &&
      tag[3].to_int() <= 57 {
      if read_u16(ctx.data, parameters) != 0 {
        raise Unsupported("stylistic-set FeatureParams version")
      }
      4
    } else if tag.length() == 4 &&
      tag.has_prefix("cv") &&
      tag[2].to_int() >= 48 &&
      tag[2].to_int() <= 57 &&
      tag[3].to_int() >= 48 &&
      tag[3].to_int() <= 57 {
      if read_u16(ctx.data, parameters) != 0 {
        raise Unsupported("character-variant FeatureParams format")
      }
      let characters = read_u16(ctx.data, parameters + 12)
      layout_span(ctx, parameters + 14, characters, 3)
      14 + characters * 3
    } else {
      raise Unsupported("unknown FeatureParams semantics for " + tag)
    }
    layout_link(out, 0, layout_leaf(ctx, parameters, size))
  }
  out
}

///|
fn layout_features(
  ctx : LayoutContext,
  pos : Int32,
  lookups : Int32,
) -> LayoutBlock raise FontError {
  let count = read_u16(ctx.data, pos)
  layout_span(ctx, pos + 2, count, 6)
  let out = layout_block(2 + count * 6)
  set_u16(out.data, 0, count)
  for i in 0..<count {
    let p = pos + 2 + i * 6
    let tag = read_tag(ctx.data, p)
    for j in 0..<4 {
      out.data[2 + i * 6 + j] = ctx.data[p + j]
    }
    layout_link(
      out,
      6 + i * 6,
      layout_feature(ctx, layout_required(ctx, pos, p + 4), tag, lookups),
    )
  }
  out
}

///|
fn freeze_gpos(
  ctx : LayoutContext,
  mark_sets : Int32,
  max_bytes : Int32,
) -> Bytes raise FontError {
  let version = read_uint32(ctx.data, 0)
  if version != 0x00010000U && version != 0x00010001U {
    raise Unsupported("GPOS version")
  }
  let header = if version == 0x00010001U { 14 } else { 10 }
  require_range(ctx.data, 0, header)
  if header == 14 && read_u32(ctx.data, 10) != 0 {
    raise Unsupported(
      "GPOS FeatureVariations require conditional feature instancing",
    )
  }
  let scripts = layout_required(ctx, 0, 4)
  let features = layout_required(ctx, 0, 6)
  let lookups = layout_required(ctx, 0, 8)
  let count = read_u16(ctx.data, lookups)
  layout_span(ctx, lookups + 2, count, 2)
  let root = layout_block(header)
  set_u32(root.data, 0, version)
  let script_bytes = serialize_layout(
    layout_scripts(ctx, scripts, read_u16(ctx.data, features)),
    ctx,
    max_bytes,
  )
  set_u16(root.data, 4, root.data.length())
  for byte in script_bytes {
    root.data.push(byte)
  }
  let feature_bytes = serialize_layout(
    layout_features(ctx, features, count),
    ctx,
    max_bytes,
  )
  set_u16(root.data, 6, root.data.length())
  for byte in feature_bytes {
    root.data.push(byte)
  }
  let list_at = root.data.length()
  set_u16(root.data, 8, list_at)
  push_u16(root.data, count)
  for _ in 0..<count {
    push_u16(root.data, 0)
  }
  let pending : Array[(Int32, Int32, Int32, Int32)] = []
  // Put every lookup and small extension header before large subtables.
  // Each ExtensionPos then has a 32-bit relocation to its own rebuilt body.
  for i in 0..<count {
    let pos = layout_required(ctx, lookups, lookups + 2 + i * 2)
    let kind = read_u16(ctx.data, pos)
    let flags = read_u16(ctx.data, pos + 2)
    let subtables = read_u16(ctx.data, pos + 4)
    layout_span(ctx, pos + 6, subtables, 2)
    if kind < 1 || kind > 9 {
      raise Unsupported("GPOS lookup type")
    }
    if (flags & 0x00E0) != 0 {
      raise Invalid("reserved GPOS lookup flags")
    }
    let output = root.data.length()
    set_u16(root.data, list_at + 2 + i * 2, output - list_at)
    push_u16(root.data, 9)
    push_u16(root.data, flags)
    push_u16(root.data, subtables)
    for _ in 0..<subtables {
      push_u16(root.data, 0)
    }
    if (flags & 16) != 0 {
      let set = read_u16(ctx.data, pos + 6 + subtables * 2)
      if set >= mark_sets {
        raise Invalid("GPOS mark-filtering set index is absent from GDEF")
      }
      push_u16(root.data, set)
    }
    let mut extension_kind = 0
    for j in 0..<subtables {
      let source = layout_required(ctx, pos, pos + 6 + j * 2)
      let (real_kind, body) = if kind == 9 {
        if read_u16(ctx.data, source) != 1 {
          raise Unsupported("GPOS ExtensionPos format")
        }
        let real_kind = read_u16(ctx.data, source + 2)
        if real_kind < 1 || real_kind > 8 {
          raise Invalid("recursive or invalid GPOS extension lookup type")
        }
        if extension_kind != 0 && extension_kind != real_kind {
          raise Invalid("mixed GPOS extension lookup types")
        }
        extension_kind = real_kind
        (real_kind, layout_required(ctx, source, source + 4, wide=true))
      } else {
        (kind, source)
      }
      pending.push((output + 6 + j * 2, output, real_kind, body))
    }
  }
  let bodies : Array[(Int32, LayoutBlock)] = []
  for (field, lookup_start, kind, pos) in pending {
    let wrapper = root.data.length()
    set_u16(root.data, field, wrapper - lookup_start)
    push_u16(root.data, 1)
    push_u16(root.data, kind)
    push_u32(root.data, 0U)
    bodies.push((wrapper, gpos_subtable(ctx, kind, pos, count)))
  }
  // Offset32 fields are relative to the extension header, not the GPOS root.
  let out = root.data.copy()
  for (wrapper, body) in bodies {
    let at = emit_layout(body, out, ctx, max_bytes, 0)
    set_u32(out, wrapper + 4, (at - wrapper).reinterpret_as_uint())
  }
  if out.length() > max_bytes {
    raise Limit("GPOS output exceeds byte budget")
  }
  Bytes::from_array(out[:])
}
