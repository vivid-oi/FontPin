///|
/// A detached catalog entry. Index zero is always the default design position.
pub struct NamedInstance {
  index : Int32
  source_index : Int32?
  name_id : Int32
  label : String
  postscript_name_id : Int32?
  coordinates : Map[String, Double]
} derive(ToJson)

///|
pub extend NamedInstance with ToJson::{to_json}

///|
// Keep only record locations while choosing labels; overlapping string pools
// must not cause every name record to allocate a fresh decoded string.
fn catalog_name_records(
  tables : Map[String, Bytes],
) -> Map[Int32, (Int32, Int32, Int32, Int32, Int32)] raise FontError {
  let data = table_required(tables, "name")
  let format = read_u16(data, 0)
  if format > 1 {
    raise Unsupported("named instances require name format 0 or 1")
  }
  let count = read_u16(data, 2)
  let base = read_u16(data, 4)
  let end = 6 + count * 12
  require_range(data, 6, count * 12)
  let tags = if format == 1 { read_u16(data, end) } else { 0 }
  let header = end + (if format == 1 { 2 + tags * 4 } else { 0 })
  require_range(data, 0, header)
  if base < header || base > data.length() {
    raise Invalid("named-instance name strings overlap records")
  }
  let result : Map[Int32, (Int32, Int32, Int32, Int32, Int32)] = Map([])
  for i in 0..<count {
    let p = 6 + i * 12
    let platform = read_u16(data, p)
    let encoding = read_u16(data, p + 2)
    let language = read_u16(data, p + 4)
    let id = read_u16(data, p + 6)
    let length = read_u16(data, p + 8)
    let start = base + read_u16(data, p + 10)
    require_range(data, start, length)
    if format == 1 && language >= 0x8000 && language - 0x8000 >= tags {
      raise Invalid("named-instance name has invalid language reference")
    }
    let rank = if platform == 3 && [0, 1, 10].contains(encoding) {
      if language == 0x409 {
        0
      } else {
        2
      }
    } else if platform == 0 && encoding <= 6 {
      1
    } else if platform == 1 && encoding == 0 {
      3
    } else {
      4
    }
    let better = match result.get(id) {
      None => true
      Some((old, _, _, _, _)) => rank < old
    }
    if better {
      result[id] = (rank, start, length, platform, encoding)
    }
  }
  result
}

///|
fn catalog_label(
  tables : Map[String, Bytes],
  records : Map[Int32, (Int32, Int32, Int32, Int32, Int32)],
  id : Int32,
) -> String raise FontError {
  guard records.get(id) is Some((rank, start, length, platform, _)) else {
    raise Invalid("named instance references missing name ID " + id.to_string())
  }
  if rank == 4 {
    raise Unsupported(
      "named-instance label encoding for name ID " + id.to_string(),
    )
  }
  if length > 4096 {
    raise Limit("named-instance labels are limited to 4096 encoded bytes")
  }
  let name = table_required(tables, "name")[start:start + length].to_owned()
  let out = StringBuilder()
  if platform == 0 || platform == 3 {
    validate_name_utf16(name)
    let mut i = 0
    while i < name.length() {
      let first = read_u16(name, i)
      i += 2
      let scalar = if first >= 0xD800 && first <= 0xDBFF {
        let low = read_u16(name, i)
        i += 2
        0x10000 + (first - 0xD800) * 1024 + low - 0xDC00
      } else {
        first
      }
      out.write_char(scalar.unsafe_to_char())
    }
  } else {
    for byte in name {
      if byte.to_int() > 127 {
        raise Unsupported(
          "named-instance Mac Roman label needs a Unicode equivalent",
        )
      }
      out.write_char(byte.to_int().unsafe_to_char())
    }
  }
  let label = out.to_string()
  if label.is_empty() {
    raise Invalid("named-instance label is empty")
  }
  label
}

///|
/// Enumerate fvar presets, including an implicit default when it is absent.
/// Labels prefer US-English Windows Unicode, Unicode-platform, other Windows
/// Unicode, then ASCII Mac Roman. The font's conversion naming policy is unchanged.
pub fn Font::named_instances(
  self : Font,
) -> Array[NamedInstance] raise FontError {
  let data = table_required(self.tables, "fvar")
  let count = read_u16(data, 12)
  if count > 1023 {
    raise Limit("named-instance catalog supports at most 1023 fvar records")
  }
  let axes = self.design_axes
  let start = read_u16(data, 4) + axes.length() * read_u16(data, 10)
  let size = read_u16(data, 14)
  let names = catalog_name_records(self.tables)
  let entries : Array[NamedInstance] = []
  let mut default_index : Int32? = None
  for i in 0..<count {
    let p = start + i * size
    let id = read_u16(data, p)
    if id != 2 && id != 17 && (id < 256 || id > 32767) {
      raise Invalid("invalid named-instance subfamily name ID")
    }
    if read_u16(data, p + 2) != 0 {
      raise Unsupported("named-instance reserved flags")
    }
    let coordinates : Map[String, Double] = Map([])
    let mut is_default = true
    for axis_index, axis in axes {
      let value = read_fixed(data, p + 4 + axis_index * 4)
      if value < axis.minimum || value > axis.maximum {
        raise Invalid(
          "named-instance coordinate outside axis range: " + axis.tag,
        )
      }
      coordinates[axis.tag] = value
      if value != axis.default {
        is_default = false
      }
    }
    if !is_default && [2, 17].contains(id) {
      raise Invalid("default name ID used by non-default instance")
    }
    let ps_id = if size == 6 + axes.length() * 4 {
      let value = read_u16(data, p + size - 2)
      if value == 65535 {
        None
      } else {
        if value != 6 && (value < 256 || value > 32767) {
          raise Invalid("invalid named-instance PostScript name ID")
        }
        if value == 6 && !is_default {
          raise Invalid(
            "default PostScript name ID used by non-default instance",
          )
        }
        if !names.contains(value) {
          raise Invalid("named-instance PostScript name ID is missing")
        }
        Some(value)
      }
    } else {
      None
    }
    if is_default && default_index is None {
      default_index = Some(i)
    }
    entries.push({
      index: i,
      source_index: Some(i),
      name_id: id,
      label: catalog_label(self.tables, names, id),
      postscript_name_id: ps_id,
      coordinates,
    })
  }
  let result : Array[NamedInstance] = []
  match default_index {
    Some(index) => result.push(entries[index])
    None => {
      let id = if names.contains(17) { 17 } else { 2 }
      let coordinates : Map[String, Double] = Map([])
      for axis in axes {
        coordinates[axis.tag] = axis.default
      }
      result.push({
        index: 0,
        source_index: None,
        name_id: id,
        label: catalog_label(self.tables, names, id),
        postscript_name_id: if names.contains(6) {
          Some(6)
        } else {
          None
        },
        coordinates,
      })
    }
  }
  for i, entry in entries {
    if default_index != Some(i) {
      result.push(entry)
    }
  }
  Array::makei(result.length(), index => { ..result[index], index, })
}

///|
/// Freeze a catalog index using the same byte and work limits as instantiate.
pub fn Font::instantiate_named(
  self : Font,
  index : Int32,
  max_bytes~ : Int32 = 32 * 1024 * 1024,
  work_limit~ : Int32 = 20_000_000,
) -> Instance raise FontError {
  let entries = self.named_instances()
  if index < 0 || index >= entries.length() {
    raise Invalid("named-instance index out of range; list presets first")
  }
  self.instantiate(entries[index].coordinates, max_bytes~, work_limit~)
}
