///|
test "hint scanner distinguishes variation opcodes from every push operand form" {
  guard_static_hints(b"", "empty")
  guard_static_hints(b"\x00\x01\x88", "ordinary")
  for opcode in 0xB0..<=0xBF {
    let count = if opcode <= 0xB7 { opcode - 0xAF } else { (opcode - 0xB7) * 2 }
    let bytes : Array[Byte] = [opcode.to_byte()]
    for i in 0..<count {
      bytes.push((if i % 2 == 0 { 0x91 } else { 0x92 }).to_byte())
    }
    guard_static_hints(Bytes::from_array(bytes[:]), "push")
  }
  for opcode in [0x40, 0x41] {
    for count in [0, 1, 2, 255] {
      let bytes : Array[Byte] = [opcode.to_byte(), count.to_byte()]
      for i in 0..<(count * (if opcode == 0x41 { 2 } else { 1 })) {
        bytes.push((if i % 2 == 0 { 0x91 } else { 0x92 }).to_byte())
      }
      guard_static_hints(Bytes::from_array(bytes[:]), "npush")
    }
  }
}

///|
test "hint scanner rejects actual variation operations including dead function bodies" {
  for opcode in [0x91, 0x92] {
    let bytes = Bytes::from_array(
      [b'\xb0', b'\x00', b'\x2c', opcode.to_byte(), b'\x2d'][:],
    )
    try guard_static_hints(bytes, "glyph 5") catch {
      Unsupported(message) =>
        assert_true(message.contains("glyph 5 hint opcode"))
      _ => fail("expected unsupported variation-dependent hint opcode")
    } noraise {
      _ => fail("expected unsupported variation-dependent hint opcode")
    }
  }
  // A pushed 0x91 is harmless, but a subsequent opcode 0x91 is not.
  try guard_static_hints(b"\xb0\x91\x91", "prep") catch {
    Unsupported(message) => assert_true(message.contains("at byte 2"))
    _ => fail("expected a variation-dependent opcode after a push")
  } noraise {
    _ => fail("expected a variation-dependent opcode after a push")
  }
}

///|
test "hint scanner rejects each truncated fixed push and variable push payload" {
  for opcode in 0xB0..<=0xBF {
    let count = if opcode <= 0xB7 { opcode - 0xAF } else { (opcode - 0xB7) * 2 }
    let valid : Array[Byte] = [opcode.to_byte()]
    for _ in 0..<count {
      valid.push(b'\x00')
    }
    for length in 1..<valid.length() {
      try
        guard_static_hints(Bytes::from_array(valid[0:length]), "glyph")
      catch {
        Invalid(_) => ()
        _ => fail("expected invalid truncated push")
      } noraise {
        _ => fail("expected invalid truncated push")
      }
    }
  }
  for bytes in [b"\x40", b"\x41", b"\x40\x01", b"\x41\x01", b"\x41\x01\x00"] {
    try guard_static_hints(bytes, "prep") catch {
      Invalid(_) => ()
      _ => fail("expected invalid truncated variable push")
    } noraise {
      _ => fail("expected invalid truncated variable push")
    }
  }
  let valid = b"\xb0\x91\x00"
  guard_static_hints(valid, "recovered")
  assert_eq(valid, b"\xb0\x91\x00")
}

///|
test "hint scanner accepts its program-size boundary and refuses oversized programs" {
  let bytes = Array::make(65535, b'\x00')
  guard_static_hints(Bytes::from_array(bytes[:]), "boundary")
  bytes.push(b'\x00')
  try guard_static_hints(Bytes::from_array(bytes[:]), "oversized") catch {
    Limit(message) => assert_true(message.contains("oversized"))
    _ => fail("expected a hint program-size limit")
  } noraise {
    _ => fail("expected a hint program-size limit")
  }
  guard_static_hints(b"\x00", "recovered")
}
