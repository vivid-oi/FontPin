///|
fn collect_glyph_points(
  glyphs : Array[FontGlyph],
  gid : Int32,
  path : Array[Int32],
  work : Ref[Int32],
  work_limit : Int32,
) -> (Array[Double], Array[Double]) raise FontError {
  if path.length() >= 64 {
    raise Limit("composite glyph nesting exceeds 64")
  }
  if path.contains(gid) {
    raise Invalid("cyclic composite glyph references")
  }
  // Empty glyphs still cost traversal work: a repeated-component DAG can
  // otherwise expand exponentially without ever contributing a leaf point.
  if work.val >= work_limit {
    raise Limit("composite traversal budget exceeded")
  }
  work.val += 1
  path.push(gid)
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  match glyphs[gid].body {
    Empty => ()
    Simple(xs=source_x, ys=source_y, ..) => {
      if source_x.length() > work_limit - work.val {
        raise Limit("composite point expansion budget exceeded")
      }
      work.val += source_x.length()
      for x in source_x {
        xs.push(x.to_double())
      }
      for y in source_y {
        ys.push(y.to_double())
      }
    }
    Composite(components~, ..) =>
      for component in components {
        let (child_x, child_y) = collect_glyph_points(
          glyphs,
          component.glyph,
          path,
          work,
          work_limit,
        )
        let mut dx = component.x.to_double()
        let mut dy = component.y.to_double()
        if (component.flags & 2) == 0 {
          if component.x < 0 || component.y < 0 {
            raise Invalid("negative composite alignment point")
          }
          if component.x >= xs.length() || component.y >= child_x.length() {
            raise Unsupported(
              "composite alignment requires unavailable contour point; phantom-point alignment is not supported",
            )
          }
          // Transform the child before aligning its point to an already
          // assembled parent point. ROUND_XY_TO_GRID/offset flags do not apply.
          dx = xs[component.x] -
            (
              child_x[component.y] * component.xx +
              child_y[component.y] * component.yx
            )
          dy = ys[component.x] -
            (
              child_x[component.y] * component.xy +
              child_y[component.y] * component.yy
            )
        } else if (component.flags & 2048) != 0 {
          let x = dx * component.xx + dy * component.yx
          let y = dx * component.xy + dy * component.yy
          dx = x
          dy = y
        }
        if (component.flags & 6) == 6 {
          dx = ot_round(dx).to_double()
          dy = ot_round(dy).to_double()
        }
        for i, x in child_x {
          xs.push(x * component.xx + child_y[i] * component.yx + dx)
          ys.push(x * component.xy + child_y[i] * component.yy + dy)
        }
      }
  }
  ignore(path.pop())
  (xs, ys)
}

///|
fn calculate_glyph_bounds(
  glyphs : Array[FontGlyph],
  gid : Int32,
  work : Ref[Int32],
  work_limit : Int32,
) -> Unit raise FontError {
  let (xs, ys) = collect_glyph_points(glyphs, gid, [], work, work_limit)
  let glyph = glyphs[gid]
  if xs.is_empty() {
    glyph.x_min = 0
    glyph.y_min = 0
    glyph.x_max = 0
    glyph.y_max = 0
  } else {
    let mut left = xs[0]
    let mut right = xs[0]
    let mut bottom = ys[0]
    let mut top = ys[0]
    for i, x in xs {
      if x < left {
        left = x
      }
      if x > right {
        right = x
      }
      if ys[i] < bottom {
        bottom = ys[i]
      }
      if ys[i] > top {
        top = ys[i]
      }
    }
    glyph.x_min = round_glyph_coordinate(left)
    glyph.x_max = round_glyph_coordinate(right)
    glyph.y_min = round_glyph_coordinate(bottom)
    glyph.y_max = round_glyph_coordinate(top)
  }
}

///|
fn encode_font_glyph(glyph : FontGlyph) -> Bytes raise FontError {
  if glyph.body is Empty {
    return b""
  }
  let out : Array[Byte] = []
  let contours = match glyph.body {
    Simple(ends~, ..) => ends.length()
    _ => -1
  }
  push_i16(out, contours)
  push_i16(out, glyph.x_min)
  push_i16(out, glyph.y_min)
  push_i16(out, glyph.x_max)
  push_i16(out, glyph.y_max)
  match glyph.body {
    Empty => ()
    Simple(ends~, flags~, xs~, ys~, instructions~) => {
      for endpoint in ends {
        push_u16(out, endpoint)
      }
      push_u16(out, instructions.length())
      for byte in instructions {
        out.push(byte)
      }
      // A full static instance can introduce overlap even when the default
      // outline did not overlap. Signal this to rasterizers, as fontTools does.
      for i, flag in flags {
        let overlap = if i == 0 { 64 } else { 0 }
        out.push(((flag & 65) | overlap).to_byte())
      }
      for points in [xs, ys] {
        let mut previous = 0
        for point in points {
          push_i16(out, point - previous)
          previous = point
        }
      }
    }
    Composite(components~, instructions~) => {
      for i, component in components {
        let mut flags = (component.flags | 1) & 65247
        if i == 0 {
          flags = flags | 1024
        }
        if i + 1 < components.length() {
          flags = flags | 32
        }
        if i + 1 == components.length() && !instructions.is_empty() {
          flags = flags | 256
        }
        push_u16(out, flags)
        push_u16(out, component.glyph)
        if (component.flags & 2) == 0 {
          push_u16(out, component.x)
          push_u16(out, component.y)
        } else {
          push_i16(out, component.x)
          push_i16(out, component.y)
        }
        for byte in component.transform {
          out.push(byte)
        }
      }
      if !instructions.is_empty() {
        push_u16(out, instructions.length())
        for byte in instructions {
          out.push(byte)
        }
      }
    }
  }
  Bytes::from_array(out[:])
}

///|
fn instantiate_glyphs(
  tables : Map[String, Bytes],
  coords : Array[Double],
  work_limit : Int32,
) -> GlyphResult raise FontError {
  if work_limit <= 0 {
    raise Limit("point-work budget must be positive")
  }
  let head = table_required(tables, "head")
  let glyph_count = read_u16(table_required(tables, "maxp"), 4)
  let metric_count = read_u16(table_required(tables, "hhea"), 34)
  if glyph_count == 0 || metric_count == 0 || metric_count > glyph_count {
    raise Invalid("invalid glyph or horizontal metric count")
  }
  let hmtx = table_required(tables, "hmtx")
  let metric_size = metric_count * 4 + (glyph_count - metric_count) * 2
  require_range(hmtx, 0, metric_size)
  if hmtx.length() != metric_size {
    raise Invalid("hmtx length does not match glyph and metric counts")
  }
  let loca = table_required(tables, "loca")
  let glyf = table_required(tables, "glyf")
  let loca_format = read_i16(head, 50)
  if loca_format != 0 && loca_format != 1 {
    raise Invalid("unsupported indexToLocFormat")
  }
  let loca_size = (glyph_count + 1) * (if loca_format == 0 { 2 } else { 4 })
  if loca.length() != loca_size {
    raise Invalid("loca length does not match glyph count")
  }
  let offsets : Array[Int32] = []
  let mut previous = 0
  for i in 0..<=glyph_count {
    let offset = if loca_format == 0 {
      read_u16(loca, i * 2) * 2
    } else {
      read_u32(loca, i * 4)
    }
    if offset < previous || offset > glyf.length() {
      raise Invalid("invalid loca offset")
    }
    offsets.push(offset)
    previous = offset
  }
  if offsets[0] != 0 {
    raise Invalid("glyf contains bytes before the first loca offset")
  }
  // Some writers include up to one word's alignment in glyf's table length.
  // Whole unreferenced data blocks are not glyph padding and cannot be dropped.
  let glyf_end = offsets[glyph_count]
  if glyf.length() - glyf_end > 3 {
    raise Invalid("glyf contains excess unreferenced trailing data")
  }
  for i in glyf_end..<glyf.length() {
    if glyf[i] != 0 {
      raise Invalid("glyf contains nonzero unreferenced trailing data")
    }
  }
  let work = Ref(0)
  let vertical = vertical_metrics(tables, glyph_count)
  let glyphs : Array[FontGlyph] = []
  for gid in 0..<glyph_count {
    let (advance, lsb) = glyph_metrics(hmtx, gid, metric_count)
    glyphs.push(
      parse_font_glyph(
        glyf[offsets[gid]:offsets[gid + 1]].to_owned(),
        advance,
        lsb,
        glyph_count,
        work,
        work_limit,
      ),
    )
  }
  let gvar = parse_gvar(
    table_required(tables, "gvar"),
    coords.length(),
    glyph_count,
  )
  let vertical_phantoms : Array[(Int32, Double)?] = []
  for gid, glyph in glyphs {
    let metric = match vertical {
      Some((data, count)) => Some(glyph_metrics(data, gid, count))
      None => None
    }
    vertical_phantoms.push(
      vary_glyph(glyph, gvar, gid, coords, work, work_limit, metric),
    )
  }
  for gid, glyph in glyphs {
    calculate_glyph_bounds(glyphs, gid, work, work_limit)
    let lsb = glyph.x_min.to_double() - glyph.lsb.to_double()
    if lsb < -32768.0 || lsb > 32767.0 {
      raise Invalid("instanced left side bearing overflow")
    }
    glyph.lsb = lsb.to_int()
  }
  let new_glyf : Array[Byte] = []
  let new_loca : Array[Byte] = []
  let new_hmtx : Array[Byte] = []
  let new_vmtx : Array[Byte] = []
  let mut x_min = 32767
  let mut y_min = 32767
  let mut x_max = -32768
  let mut y_max = -32768
  for gid, glyph in glyphs {
    push_u32(new_loca, new_glyf.length().reinterpret_as_uint())
    let data = encode_font_glyph(glyph)
    if data.length() > 64_000_000 - new_glyf.length() {
      raise Limit("instanced outlines exceed 64 MB")
    }
    for byte in data {
      new_glyf.push(byte)
    }
    if new_glyf.length() % 2 != 0 {
      new_glyf.push(0)
    }
    push_u16(new_hmtx, glyph.advance)
    push_i16(new_hmtx, glyph.lsb)
    if vertical_phantoms[gid] is Some((height, top)) {
      let bearing = top - glyph.y_max.to_double()
      if bearing < -32768.5 || bearing >= 32767.5 {
        raise Invalid("instanced top side bearing overflow")
      }
      push_u16(new_vmtx, height)
      push_i16(new_vmtx, ot_round(bearing))
    }
    if data.length() > 0 {
      if glyph.x_min < x_min {
        x_min = glyph.x_min
      }
      if glyph.y_min < y_min {
        y_min = glyph.y_min
      }
      if glyph.x_max > x_max {
        x_max = glyph.x_max
      }
      if glyph.y_max > y_max {
        y_max = glyph.y_max
      }
    }
  }
  if x_min == 32767 && x_max == -32768 {
    x_min = 0
    y_min = 0
    x_max = 0
    y_max = 0
  }
  push_u32(new_loca, new_glyf.length().reinterpret_as_uint())
  {
    glyf: Bytes::from_array(new_glyf[:]),
    loca: Bytes::from_array(new_loca[:]),
    hmtx: Bytes::from_array(new_hmtx[:]),
    vmtx: if vertical is Some(_) {
      Some(Bytes::from_array(new_vmtx[:]))
    } else {
      None
    },
    x_min,
    y_min,
    x_max,
    y_max,
    glyph_count,
  }
}
