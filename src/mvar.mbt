///|
// MVAR value tags and target offsets follow OpenType 1.9.1.
// https://learn.microsoft.com/en-us/typography/opentype/spec/mvar
// Synchronizing originally-identical OS/2 and hhea vertical metrics follows
// fontTools.varLib.instancer.instantiateMVAR (MIT).
fn mvar_target(tag : String) -> (String, Int32, Bool) raise FontError {
  match tag {
    "hasc" => ("OS/2", 68, false)
    "hdsc" => ("OS/2", 70, false)
    "hlgp" => ("OS/2", 72, false)
    "hcla" => ("OS/2", 74, true)
    "hcld" => ("OS/2", 76, true)
    "vasc" => ("vhea", 4, false)
    "vdsc" => ("vhea", 6, false)
    "vlgp" => ("vhea", 8, false)
    "hcrs" => ("hhea", 18, false)
    "hcrn" => ("hhea", 20, false)
    "hcof" => ("hhea", 22, false)
    "vcrs" => ("vhea", 18, false)
    "vcrn" => ("vhea", 20, false)
    "vcof" => ("vhea", 22, false)
    "xhgt" => ("OS/2", 86, false)
    "cpht" => ("OS/2", 88, false)
    "sbxs" => ("OS/2", 10, false)
    "sbys" => ("OS/2", 12, false)
    "sbxo" => ("OS/2", 14, false)
    "sbyo" => ("OS/2", 16, false)
    "spxs" => ("OS/2", 18, false)
    "spys" => ("OS/2", 20, false)
    "spxo" => ("OS/2", 22, false)
    "spyo" => ("OS/2", 24, false)
    "strs" => ("OS/2", 26, false)
    "stro" => ("OS/2", 28, false)
    "unds" => ("post", 10, false)
    "undo" => ("post", 8, false)
    _ =>
      if tag.length() == 4 &&
        tag.has_prefix("gsp") &&
        tag[3] >= '0' &&
        tag[3] <= '9' {
        ("gasp", 4 + (tag[3].to_int() - 48) * 4, true)
      } else {
        raise Unsupported("unrecognized MVAR metric tag: " + tag)
      }
  }
}

///|
fn apply_mvar(
  tables : Map[String, Bytes],
  coords : Array[Double],
  work_limit~ : Int32 = 20_000_000,
) -> Unit raise FontError {
  guard tables.get("MVAR") is Some(data) else { return }
  if work_limit < 1 {
    raise Limit("MVAR work budget must be positive")
  }
  require_range(data, 0, 12)
  if read_u16(data, 0) != 1 || read_u16(data, 2) != 0 {
    raise Unsupported("MVAR version is not 1.0")
  }
  if read_u16(data, 4) != 0 {
    raise Invalid("MVAR reserved field is nonzero")
  }
  let record_size = read_u16(data, 6)
  let count = read_u16(data, 8)
  let store_offset = read_u16(data, 10)
  if record_size < 8 {
    raise Invalid("MVAR record is smaller than 8 bytes")
  }
  if record_size > 8 {
    raise Unsupported("extended MVAR value records are not supported")
  }
  iv_span(data, 12, count, record_size)
  if count == 0 {
    if store_offset != 0 {
      raise Invalid("empty MVAR must not have a variation store")
    }
    if data.length() != 12 {
      raise Unsupported("unexplained bytes after empty MVAR header")
    }
    return
  }
  if store_offset < 12 + count * record_size {
    raise Invalid("MVAR variation store overlaps records")
  }
  let store = variation_store(data, store_offset, coords, work_limit~)
  let changes : Map[String, Bytes] = Map([])
  let mut previous = ""
  let mut work = 0
  for i in 0..<count {
    let pos = 12 + i * record_size
    let tag = read_tag(data, pos)
    if i > 0 && String::lexical_compare(previous, tag) >= 0 {
      raise Invalid("MVAR metric tags are not strictly sorted")
    }
    previous = tag
    let (target, offset, unsigned) = mvar_target(tag)
    let original = changes
      .get(target)
      .unwrap_or_else(() => table_required(tables, target))
    if target == "OS/2" && offset >= 86 && read_u16(original, 0) < 2 {
      raise Invalid("MVAR x-height or cap-height needs OS/2 version 2 or newer")
    }
    if target == "gasp" {
      let version = read_u16(original, 0)
      let ranges = read_u16(original, 2)
      if version > 1 {
        raise Unsupported("MVAR gasp version is not 0 or 1")
      }
      iv_span(original, 4, ranges, 4)
      if ranges == 0 || (offset - 4) / 4 >= ranges - 1 {
        raise Invalid("MVAR gasp target is absent or the terminal range")
      }
    }
    let base = if unsigned {
      read_u16(original, offset)
    } else {
      read_i16(original, offset)
    }
    let outer = read_u16(data, pos + 4)
    let inner = read_u16(data, pos + 6)
    let charge = variation_work(store, outer, inner)
    if charge > work_limit - work {
      raise Limit("MVAR delta evaluation budget exceeded")
    }
    work += charge
    let delta = variation_delta(store, outer, inner)
    let value = base.to_double() + delta
    if value < (if unsigned { -0.5 } else { -32768.5 }) ||
      value >= (if unsigned { 65535.5 } else { 32767.5 }) {
      raise Invalid("MVAR metric overflow: " + tag)
    }
    let output = byte_array(original)
    if unsigned {
      set_u16(output, offset, ot_round(value))
    } else {
      set_i16(output, offset, ot_round(value))
    }
    changes[target] = Bytes::from_array(output[:])
  }
  if changes.get("gasp") is Some(gasp) {
    let count = read_u16(gasp, 2)
    let mut previous = -1
    for i in 0..<count {
      let last = read_u16(gasp, 4 + i * 4)
      if last <= previous {
        raise Invalid("MVAR produces non-increasing gasp ranges")
      }
      previous = last
    }
    if previous != 65535 {
      raise Invalid("gasp terminal range is not 65535")
    }
  }
  if changes.get("OS/2") is Some(os2) &&
    tables.get("OS/2") is Some(old_os2) &&
    tables.get("hhea") is Some(old_hhea) {
    if old_os2.length() >= 74 &&
      old_hhea.length() >= 10 &&
      read_i16(old_os2, 68) == read_i16(old_hhea, 4) &&
      read_i16(old_os2, 70) == read_i16(old_hhea, 6) &&
      read_i16(old_os2, 72) == read_i16(old_hhea, 8) {
      let hhea = byte_array(changes.get("hhea").unwrap_or(old_hhea))
      set_i16(hhea, 4, read_i16(os2, 68))
      set_i16(hhea, 6, read_i16(os2, 70))
      set_i16(hhea, 8, read_i16(os2, 72))
      changes["hhea"] = Bytes::from_array(hhea[:])
    }
  }
  // Publish only after all records and aggregate invariants have been checked.
  for tag, bytes in changes {
    tables[tag] = bytes
  }
}
