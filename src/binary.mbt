///|
fn require_range(
  data : Bytes,
  pos : Int32,
  size : Int32,
) -> Unit raise FontError {
  if pos < 0 || size < 0 || pos > data.length() || size > data.length() - pos {
    raise Invalid(
      "truncated or out-of-range font data at byte " + pos.to_string(),
    )
  }
}

///|
fn read_u8(data : Bytes, pos : Int32) -> Int32 raise FontError {
  require_range(data, pos, 1)
  data[pos].to_int()
}

///|
fn read_u16(data : Bytes, pos : Int32) -> Int32 raise FontError {
  require_range(data, pos, 2)
  (data[pos].to_int() << 8) | data[pos + 1].to_int()
}

///|
fn read_i16(data : Bytes, pos : Int32) -> Int32 raise FontError {
  let n = read_u16(data, pos)
  if n >= 32768 {
    n - 65536
  } else {
    n
  }
}

///|
fn read_uint32(data : Bytes, pos : Int32) -> UInt32 raise FontError {
  require_range(data, pos, 4)
  (data[pos].to_uint() << 24) |
  (data[pos + 1].to_uint() << 16) |
  (data[pos + 2].to_uint() << 8) |
  data[pos + 3].to_uint()
}

///|
fn read_u32(data : Bytes, pos : Int32) -> Int32 raise FontError {
  let n = read_uint32(data, pos)
  if n > 2147483647U {
    raise Limit("font offset or count exceeds signed 32-bit budget")
  }
  n.reinterpret_as_int()
}

///|
fn read_fixed(data : Bytes, pos : Int32) -> Double raise FontError {
  read_uint32(data, pos).reinterpret_as_int().to_double() / 65536.0
}

///|
fn read_f2dot14(data : Bytes, pos : Int32) -> Double raise FontError {
  read_i16(data, pos).to_double() / 16384.0
}

///|
fn read_tag(data : Bytes, pos : Int32) -> String raise FontError {
  require_range(data, pos, 4)
  let s = StringBuilder()
  for i in 0..<4 {
    let n = data[pos + i].to_int()
    if n < 32 || n > 126 {
      raise Invalid("non-ASCII table or axis tag")
    }
    s.write_char(n.unsafe_to_char())
  }
  s.to_string()
}

///|
fn byte_array(data : Bytes) -> Array[Byte] {
  Array::makei(data.length(), i => data[i])
}

///|
fn set_u16(
  out : Array[Byte],
  pos : Int32,
  value : Int32,
) -> Unit raise FontError {
  if pos < 0 || pos + 2 > out.length() || value < 0 || value > 65535 {
    raise Invalid("16-bit field overflow or invalid offset")
  }
  out[pos] = (value >> 8).to_byte()
  out[pos + 1] = value.to_byte()
}

///|
fn set_i16(
  out : Array[Byte],
  pos : Int32,
  value : Int32,
) -> Unit raise FontError {
  if value < -32768 || value > 32767 {
    raise Invalid("signed 16-bit field overflow")
  }
  set_u16(out, pos, value & 65535)
}

///|
fn set_u32(
  out : Array[Byte],
  pos : Int32,
  value : UInt32,
) -> Unit raise FontError {
  if pos < 0 || pos + 4 > out.length() {
    raise Invalid("32-bit field offset out of bounds")
  }
  out[pos] = (value >> 24).to_byte()
  out[pos + 1] = (value >> 16).to_byte()
  out[pos + 2] = (value >> 8).to_byte()
  out[pos + 3] = value.to_byte()
}

///|
fn push_u16(out : Array[Byte], value : Int32) -> Unit raise FontError {
  if value < 0 || value > 65535 {
    raise Invalid("16-bit field overflow")
  }
  out.push((value >> 8).to_byte())
  out.push(value.to_byte())
}

///|
fn push_i16(out : Array[Byte], value : Int32) -> Unit raise FontError {
  if value < -32768 || value > 32767 {
    raise Invalid("signed 16-bit field overflow")
  }
  push_u16(out, value & 65535)
}

///|
fn push_u32(out : Array[Byte], value : UInt32) -> Unit {
  out.push((value >> 24).to_byte())
  out.push((value >> 16).to_byte())
  out.push((value >> 8).to_byte())
  out.push(value.to_byte())
}

///|
fn table_required(
  tables : Map[String, Bytes],
  tag : String,
) -> Bytes raise FontError {
  match tables.get(tag) {
    Some(data) => data
    None => raise Invalid("missing required table: " + tag)
  }
}

///|
fn ot_round(value : Double) -> Int32 {
  @math.floor(value + 0.5).to_int()
}
