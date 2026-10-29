///|
priv struct GlyphComponent {
  flags : Int32
  glyph : Int32
  mut x : Int32
  mut y : Int32
  xx : Double
  xy : Double
  yx : Double
  yy : Double
  transform : Bytes
}

///|
priv enum GlyphBody {
  Empty
  Simple(
    ends~ : Array[Int32],
    flags~ : Array[Int32],
    xs~ : Array[Int32],
    ys~ : Array[Int32],
    instructions~ : Bytes
  )
  Composite(components~ : Array[GlyphComponent], instructions~ : Bytes)
}

///|
priv struct FontGlyph {
  body : GlyphBody
  mut x_min : Int32
  mut y_min : Int32
  mut x_max : Int32
  mut y_max : Int32
  mut advance : Int32
  mut lsb : Int32
}

///|
priv struct GlyphResult {
  glyf : Bytes
  loca : Bytes
  hmtx : Bytes
  vmtx : Bytes?
  x_min : Int32
  y_min : Int32
  x_max : Int32
  y_max : Int32
  glyph_count : Int32
}

///|
fn round_glyph_coordinate(value : Double) -> Int32 raise FontError {
  // Check before conversion: deeply nested transforms or accumulated tuples
  // can exceed Int32 as well as the TrueType signed 16-bit coordinate domain.
  if value.is_nan() || value < -32768.5 || value >= 32767.5 {
    raise Invalid("instanced glyph coordinate overflow")
  }
  ot_round(value)
}

///|
fn glyph_metrics(
  hmtx : Bytes,
  gid : Int32,
  metric_count : Int32,
) -> (Int32, Int32) raise FontError {
  if gid < metric_count {
    (read_u16(hmtx, gid * 4), read_i16(hmtx, gid * 4 + 2))
  } else {
    (
      read_u16(hmtx, (metric_count - 1) * 4),
      read_i16(hmtx, metric_count * 4 + (gid - metric_count) * 2),
    )
  }
}

///|
fn parse_font_glyph(
  data : Bytes,
  advance : Int32,
  lsb : Int32,
  glyph_count : Int32,
  work : Ref[Int32],
  work_limit : Int32,
) -> FontGlyph raise FontError {
  if data.length() == 0 {
    return {
      body: Empty,
      x_min: 0,
      y_min: 0,
      x_max: 0,
      y_max: 0,
      advance,
      lsb,
    }
  }
  require_range(data, 0, 10)
  let contours = read_i16(data, 0)
  let x_min = read_i16(data, 2)
  let y_min = read_i16(data, 4)
  let x_max = read_i16(data, 6)
  let y_max = read_i16(data, 8)
  if x_min > x_max || y_min > y_max {
    raise Invalid("invalid glyph bounding box")
  }
  let cursor : GvarCursor = { data, pos: 10, end: data.length(), }
  let body = if contours >= 0 {
    let ends : Array[Int32] = []
    for _ in 0..<contours {
      let point = cursor.u16()
      if !ends.is_empty() && point <= ends[ends.length() - 1] {
        raise Invalid("non-increasing glyph contour ends")
      }
      ends.push(point)
    }
    let point_count = if ends.is_empty() {
      0
    } else {
      ends[ends.length() - 1] + 1
    }
    if point_count > work_limit - work.val {
      raise Limit("glyph point-work budget exceeded")
    }
    work.val += point_count
    // A zero-contour glyph may end after its 10-byte header. If present,
    // instructions still operate on phantom points and must be preserved.
    let instruction_length = if contours == 0 && cursor.pos == cursor.end {
      0
    } else {
      cursor.u16()
    }
    require_range(data, cursor.pos, instruction_length)
    let instructions = data[cursor.pos:cursor.pos + instruction_length].to_owned()
    cursor.pos += instruction_length
    guard_static_hints(instructions, "simple glyph")
    let flags : Array[Int32] = []
    while flags.length() < point_count {
      let flag = cursor.u8()
      if (flag & 128) != 0 {
        raise Invalid("reserved simple glyph flag")
      }
      let count = if (flag & 8) != 0 { cursor.u8() + 1 } else { 1 }
      if count > point_count - flags.length() {
        raise Invalid("glyph flag run exceeds point count")
      }
      for _ in 0..<count {
        flags.push(flag & 247)
      }
    }
    let xs : Array[Int32] = []
    let ys : Array[Int32] = []
    for x_axis in [true, false] {
      let points = if x_axis { xs } else { ys }
      let short_bit = if x_axis { 2 } else { 4 }
      let same_bit = if x_axis { 16 } else { 32 }
      let mut previous = 0
      for flag in flags {
        let delta = if (flag & short_bit) != 0 {
          let byte = cursor.u8()
          if (flag & same_bit) != 0 {
            byte
          } else {
            -byte
          }
        } else if (flag & same_bit) != 0 {
          0
        } else {
          let n = cursor.u16()
          if n >= 32768 {
            n - 65536
          } else {
            n
          }
        }
        previous += delta
        if previous < -32768 || previous > 32767 {
          raise Invalid("glyph coordinate outside signed 16-bit range")
        }
        points.push(previous)
      }
    }
    Simple(ends~, flags~, xs~, ys~, instructions~)
  } else {
    if contours != -1 {
      raise Invalid("invalid composite glyph contour count")
    }
    let components : Array[GlyphComponent] = []
    let mut more = true
    let mut have_instructions = false
    while more {
      if work.val >= work_limit {
        raise Limit("glyph component-work budget exceeded")
      }
      work.val += 1
      let flags = cursor.u16()
      if (flags & 57360) != 0 {
        raise Invalid("reserved composite glyph flags")
      }
      let glyph = cursor.u16()
      if glyph >= glyph_count {
        raise Invalid("composite glyph reference out of range")
      }
      if (flags & 2) == 0 {
        raise Unsupported(
          "point-matched composite glyphs are not yet supported",
        )
      }
      let (x, y) = if (flags & 1) != 0 {
        let a = cursor.u16()
        let b = cursor.u16()
        (
          if a >= 32768 {
            a - 65536
          } else {
            a
          },
          if b >= 32768 {
            b - 65536
          } else {
            b
          },
        )
      } else {
        let a = cursor.u8()
        let b = cursor.u8()
        (if a >= 128 { a - 256 } else { a }, if b >= 128 { b - 256 } else { b })
      }
      let transform_start = cursor.pos
      let scale_flags = flags & 200
      let (xx, xy, yx, yy) = if scale_flags == 8 {
        let scale = cursor.f14()
        (scale, 0.0, 0.0, scale)
      } else if scale_flags == 64 {
        let sx = cursor.f14()
        let sy = cursor.f14()
        (sx, 0.0, 0.0, sy)
      } else if scale_flags == 128 {
        (cursor.f14(), cursor.f14(), cursor.f14(), cursor.f14())
      } else if scale_flags == 0 {
        (1.0, 0.0, 0.0, 1.0)
      } else {
        raise Invalid("conflicting composite transform flags")
      }
      if (flags & 6144) == 6144 {
        raise Invalid("conflicting composite offset flags")
      }
      components.push({
        flags,
        glyph,
        x,
        y,
        xx,
        xy,
        yx,
        yy,
        transform: data[transform_start:cursor.pos].to_owned(),
      })
      more = (flags & 32) != 0
      have_instructions = have_instructions || (flags & 256) != 0
    }
    let instructions = if have_instructions {
      let n = cursor.u16()
      require_range(data, cursor.pos, n)
      let result = data[cursor.pos:cursor.pos + n].to_owned()
      cursor.pos += n
      result
    } else {
      b""
    }
    guard_static_hints(instructions, "composite glyph")
    Composite(components~, instructions~)
  }
  // TrueType permits arbitrary alignment bytes after a glyph; they are not
  // glyph semantics and are replaced by deterministic zero alignment.
  { body, x_min, y_min, x_max, y_max, advance, lsb, }
}

///|
fn vary_glyph(
  glyph : FontGlyph,
  variation : GvarTable,
  gid : Int32,
  coords : Array[Double],
  work : Ref[Int32],
  work_limit : Int32,
  vertical : (Int32, Int32)?,
) -> (Int32, Double)? raise FontError {
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  let ends = match glyph.body {
    Empty => []
    Simple(xs=points_x, ys=points_y, ends~, ..) => {
      for x in points_x {
        xs.push(x.to_double())
      }
      for y in points_y {
        ys.push(y.to_double())
      }
      ends
    }
    Composite(components~, ..) => {
      for component in components {
        xs.push(component.x.to_double())
        ys.push(component.y.to_double())
      }
      []
    }
  }
  let real_points = xs.length()
  let left = glyph.x_min - glyph.lsb
  xs.push(left.to_double())
  xs.push((left + glyph.advance).to_double())
  xs.push(0.0)
  xs.push(0.0)
  let (top, bottom) = match vertical {
    Some((height, tsb)) => {
      let top = glyph.y_max + tsb
      (top.to_double(), (top - height).to_double())
    }
    None => (0.0, 0.0)
  }
  ys.push(0.0)
  ys.push(0.0)
  ys.push(top)
  ys.push(bottom)
  apply_gvar(variation, gid, coords, xs, ys, ends, work, work_limit)
  match glyph.body {
    Empty => ()
    Simple(xs=points_x, ys=points_y, ..) =>
      for i in 0..<real_points {
        points_x[i] = round_glyph_coordinate(xs[i])
        points_y[i] = round_glyph_coordinate(ys[i])
      }
    Composite(components~, ..) =>
      for i, component in components {
        component.x = round_glyph_coordinate(xs[i])
        component.y = round_glyph_coordinate(ys[i])
      }
  }
  // Phantom points may lie outside the outline's signed 16-bit domain, but
  // must not overflow Int32 before a bounded final metric is calculated.
  let left = @math.floor(xs[real_points] + 0.5)
  let right = @math.floor(xs[real_points + 1] + 0.5)
  if left < -2147483648.0 ||
    left > 2147483647.0 ||
    right - left < 0.0 ||
    right - left > 65535.0 {
    raise Invalid("instanced horizontal phantom metric overflow")
  }
  glyph.advance = (right - left).to_int()
  // Recomputed after the final glyph bounds are known.
  glyph.lsb = left.to_int()
  match vertical {
    None => None
    Some(_) => {
      let top = ys[real_points + 2]
      let height = top - ys[real_points + 3]
      if top.is_nan() ||
        top < -2147483648.0 ||
        top > 2147483647.0 ||
        height < -0.5 ||
        height >= 65535.5 {
        raise Invalid("instanced vertical phantom metric overflow")
      }
      Some((ot_round(height), top))
    }
  }
}
