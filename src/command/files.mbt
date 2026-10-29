// SPDX-License-Identifier: Apache-2.0
// File-publication workflow adapted from vivid-oi/MBTRelMask (Apache-2.0).
// See THIRD_PARTY.md and LICENSES/Apache-2.0.txt.

///|
async fn read_font(path : String) -> Bytes {
  let file = @fs.open(path[:], mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular || file.size() > 32_000_000L {
    fail("input must be a regular file of at most 32000000 bytes")
  }
  let buffer = @buffer.Buffer()
  while file.read_some(max_len=65536) is Some(bytes) {
    if bytes.length() > 32_000_000 - buffer.length() {
      fail("input grew past the 32000000-byte limit")
    }
    buffer.write_bytes(bytes[:])
  }
  buffer.to_bytes()
}

///|
async fn publish_font(destination : String, bytes : Bytes) -> Unit {
  guard @env.rand(16) is Some(random) else {
    fail("temporary name unavailable")
  }
  let suffix = StringBuilder()
  let digits = "0123456789abcdef".to_array()
  for b in random {
    suffix.write_char(digits[b.to_int() >> 4])
    suffix.write_char(digits[b.to_int() & 15])
  }
  let temporary = destination + "." + suffix.to_string() + ".pending"
  @async.protect_from_cancel(() => {
    let file = @fs.create(temporary[:], allow_existing=false, permission=0o644)
    let mut published = false
    defer (if !published {
      @fs.remove(temporary[:]) catch {
        _ => @stdio.stderr.write("cleanup failed: remove " + temporary + "\n")
      }
    })
    {
      defer file.close()
      file.write(bytes)
      file.sync()
    }
    @fs.rename(temporary[:], destination[:], replace=false)
    published = true
  })
}
