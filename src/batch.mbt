///|
priv enum BatchSelection {
  Coordinates(Map[String, Double])
  Preset(Int32)
}

///|
priv struct BatchRequest {
  filename : String
  selection : BatchSelection
}

///|
pub struct BatchPlan {
  priv requests : Array[BatchRequest]
}

///|
pub struct BatchArtifact {
  filename : String
  instance : Instance
}

///|
fn portable_batch_filename(filename : String) -> String raise FontError {
  if filename.length() < 5 ||
    filename.length() > 100 ||
    !filename.has_suffix(".ttf") {
    raise Invalid(
      "batch file must be a 1..96-character ASCII stem followed by .ttf",
    )
  }
  let stem = filename[0:filename.length() - 4]
  let lower = StringBuilder()
  for ch in stem {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      lower.write_char((code + 32).unsafe_to_char())
    } else if (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code == 45 ||
      code == 95 {
      lower.write_char(ch)
    } else {
      raise Invalid(
        "batch file stem permits only ASCII letters, digits, hyphen and underscore",
      )
    }
  }
  let key = lower.to_string()
  if ["con", "prn", "aux", "nul"].contains(key) ||
    (
      key.length() == 4 &&
      (key.has_prefix("com") || key.has_prefix("lpt")) &&
      key[3].to_int() >= 49 &&
      key[3].to_int() <= 57
    ) {
    raise Invalid("batch file is a reserved device name")
  }
  key + ".ttf"
}

///|
// The pinned JSON parser accepts duplicate keys. After validating JSON syntax,
// scan its structural tokens and decode key strings to reject duplicates even
// when equivalent keys use different escapes. No replacement values are lost.
fn reject_batch_duplicate_keys(input : String) -> Unit raise FontError {
  let contexts : Array[Map[String, Unit]?] = []
  let mut key_expected = false
  let mut i = 0
  while i < input.length() {
    match input[i].to_int() {
      123 => {
        contexts.push(Some(Map([])))
        key_expected = true
        i += 1
      }
      91 => {
        contexts.push(None)
        key_expected = false
        i += 1
      }
      125 | 93 => {
        ignore(contexts.pop())
        key_expected = false
        i += 1
      }
      44 => {
        key_expected = !contexts.is_empty() &&
          contexts[contexts.length() - 1] is Some(_)
        i += 1
      }
      58 => {
        key_expected = false
        i += 1
      }
      34 => {
        let start = i
        i += 1
        while i < input.length() && input[i].to_int() != 34 {
          i += if input[i].to_int() == 92 { 2 } else { 1 }
        }
        i += 1
        if key_expected &&
          !contexts.is_empty() &&
          contexts[contexts.length() - 1] is Some(keys) {
          let key = @json.parse(input[start:i], max_nesting_depth=16) catch {
            _ => raise Invalid("invalid batch key string")
          }
          guard key is String(text) else {
            raise Invalid("batch key is not a string")
          }
          if keys.contains(text) {
            raise Invalid("duplicate batch JSON key: " + text)
          }
          keys[text] = ()
          key_expected = false
        }
      }
      _ => i += 1
    }
  }
}

///|
/// Parse a version-1 manifest with 1..16 distinct portable .ttf filenames.
/// Unknown fields, duplicate JSON keys and ambiguous selectors are refused.
pub fn BatchPlan::parse(input : String) -> BatchPlan raise FontError {
  if input.length() > 65536 {
    raise Limit("batch manifest exceeds 65536 UTF-16 code units")
  }
  let value = @json.parse(input[:], max_nesting_depth=16) catch {
    error => raise Invalid("batch JSON: " + error.to_string())
  }
  reject_batch_duplicate_keys(input)
  guard value is Object(root) else {
    raise Invalid("batch manifest must be an object")
  }
  for key, _ in root {
    if !["version", "outputs"].contains(key) {
      raise Invalid("unknown batch field: " + key)
    }
  }
  if root.get("version") != Some(Json::number(1.0)) {
    raise Unsupported("batch manifest version must be 1")
  }
  guard root.get("outputs") is Some(Array(outputs)) else {
    raise Invalid("batch outputs must be an array")
  }
  if outputs.is_empty() || outputs.length() > 16 {
    raise Limit("batch must contain 1..16 outputs")
  }
  let used : Map[String, Unit] = Map([])
  let requests : Array[BatchRequest] = []
  for item in outputs {
    guard item is Object(fields) else {
      raise Invalid("batch output must be an object")
    }
    for key, _ in fields {
      if !["file", "coordinates", "preset"].contains(key) {
        raise Invalid("unknown batch output field: " + key)
      }
    }
    guard fields.get("file") is Some(String(filename)) else {
      raise Invalid("batch output requires a file string")
    }
    let normalized = portable_batch_filename(filename)
    if used.contains(normalized) {
      raise Invalid("duplicate batch filename ignoring ASCII case: " + filename)
    }
    used[normalized] = ()
    let selection = match (fields.get("coordinates"), fields.get("preset")) {
      (Some(Object(values)), None) => {
        if values.length() > 32 {
          raise Limit("batch coordinate count exceeds 32")
        }
        let coordinates : Map[String, Double] = Map([])
        let keys = values.keys().to_array()
        keys.sort_by((a, b) => a.lexical_compare(b))
        for tag in keys {
          if tag.length() != 4 {
            raise Invalid("batch axis tags must have four ASCII characters")
          }
          for ch in tag {
            if ch.to_int() < 32 || ch.to_int() > 126 {
              raise Invalid("non-ASCII batch axis tag")
            }
          }
          guard values[tag] is Number(number, ..) else {
            raise Invalid("batch coordinate is not numeric: " + tag)
          }
          if number.is_nan() || number.is_inf() {
            raise Invalid("batch coordinate must be finite: " + tag)
          }
          coordinates[tag] = number
        }
        Coordinates(coordinates)
      }
      (None, Some(Number(index, ..))) => {
        if index.is_nan() ||
          index.is_inf() ||
          index < 0.0 ||
          index > 1023.0 ||
          @math.floor(index) != index {
          raise Invalid("batch preset must be an integer in 0..1023")
        }
        Preset(index.to_int())
      }
      _ =>
        raise Invalid(
          "batch output must select exactly one coordinates object or preset integer",
        )
    }
    requests.push({ filename, selection, })
  }
  requests.sort_by((a, b) => a.filename.lexical_compare(b.filename))
  { requests, }
}

///|
pub fn BatchPlan::filenames(self : BatchPlan) -> Array[String] {
  self.requests.map(request => request.filename)
}

///|
/// Return a fresh, canonical manifest value; filenames and axis keys are sorted.
pub fn BatchPlan::to_json(self : BatchPlan) -> Json {
  let outputs : Array[Json] = self.requests.map(request => {
    match request.selection {
      Coordinates(values) =>
        { "file": Json(request.filename), "coordinates": Json(values) }
      Preset(index) => { "file": Json(request.filename), "preset": Json(index) }
    }
  })
  { "version": 1, "outputs": Json(outputs) }
}

///|
/// Validate every request before instancing. No partial artifact list escapes
/// on failure; max_total_bytes bounds retained outputs, not peak process memory.
pub fn Font::instantiate_batch(
  self : Font,
  plan : BatchPlan,
  max_total_bytes~ : Int32 = 64 * 1024 * 1024,
  max_bytes~ : Int32 = 32 * 1024 * 1024,
  work_limit~ : Int32 = 20_000_000,
) -> Array[BatchArtifact] raise FontError {
  if max_total_bytes < 1024 || max_total_bytes > 128 * 1024 * 1024 {
    raise Limit("batch total-byte budget must be 1024..134217728")
  }
  let needs_presets = plan.requests.any(request => {
    request.selection is Preset(_)
  })
  let presets = if needs_presets { self.named_instances() } else { [] }
  let positions : Array[Map[String, Double]] = []
  for request in plan.requests {
    let coordinates = match request.selection {
      Coordinates(values) => values
      Preset(index) => {
        if index >= presets.length() {
          raise Invalid(
            "batch " + request.filename + ": preset index out of range",
          )
        }
        presets[index].coordinates
      }
    }
    ignore(normalized_coordinates(self, coordinates)) catch {
      Invalid(detail) =>
        raise Invalid("batch " + request.filename + ": " + detail)
      Unsupported(detail) =>
        raise Unsupported("batch " + request.filename + ": " + detail)
      Limit(detail) => raise Limit("batch " + request.filename + ": " + detail)
    }
    positions.push(coordinates)
  }
  let result : Array[BatchArtifact] = []
  let mut total = 0
  for i, request in plan.requests {
    let instance = self.instantiate(positions[i], max_bytes~, work_limit~) catch {
      Invalid(detail) =>
        raise Invalid("batch " + request.filename + ": " + detail)
      Unsupported(detail) =>
        raise Unsupported("batch " + request.filename + ": " + detail)
      Limit(detail) => raise Limit("batch " + request.filename + ": " + detail)
    }
    let size = instance.to_bytes().length()
    if size > max_total_bytes - total {
      raise Limit("batch total-byte budget exceeded before " + request.filename)
    }
    total += size
    result.push({ filename: request.filename, instance, })
  }
  result
}
