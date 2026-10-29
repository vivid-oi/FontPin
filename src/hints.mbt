///|
// Inspect instruction boundaries without interpreting the TrueType program.
// GETVARIATION is specified at:
// https://learn.microsoft.com/en-us/typography/opentype/spec/tt_instructions#get-variation
// GETDATA changes dispatch between variable/static fonts in FreeType 2.14.1:
// https://github.com/freetype/freetype/blob/VER-2-14-1/src/truetype/ttinterp.c
// These two opcodes require a deliberate hint-program transformation before
// fvar can be removed; preserving the source bytes alone is insufficient.
fn guard_static_hints(data : Bytes, context : String) -> Unit raise FontError {
  if data.length() > 65535 {
    raise Limit("TrueType hint program exceeds 65535 bytes: " + context)
  }
  let mut pos = 0
  while pos < data.length() {
    let start = pos
    let opcode = read_u8(data, pos)
    pos += 1
    if opcode == 0x91 || opcode == 0x92 {
      let name = if opcode == 0x91 { "GETVARIATION" } else { "GETDATA" }
      raise Unsupported(
        "\{context} hint opcode \{name} at byte \{start} needs axis-aware rewriting",
      )
    }
    let payload = if opcode == 0x40 || opcode == 0x41 {
      if pos == data.length() {
        raise Invalid("\{context} truncated hint push count at byte \{start}")
      }
      let count = read_u8(data, pos)
      pos += 1
      count * (if opcode == 0x41 { 2 } else { 1 })
    } else if opcode >= 0xB0 && opcode <= 0xB7 {
      opcode - 0xAF
    } else if opcode >= 0xB8 && opcode <= 0xBF {
      (opcode - 0xB7) * 2
    } else {
      0
    }
    if payload > data.length() - pos {
      raise Invalid("\{context} truncated hint push payload at byte \{start}")
    }
    pos += payload
  }
}
