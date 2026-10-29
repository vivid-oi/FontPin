///|
test "STAT retains static axes, prunes unmatched pinned values and checks indices" {
  let stat = Array::make(62, (0 : Byte))
  set_u16(stat, 0, 1)
  set_u16(stat, 2, 1)
  set_u16(stat, 4, 8)
  set_u16(stat, 6, 2)
  set_u32(stat, 8, 20U)
  set_u16(stat, 12, 2)
  set_u32(stat, 14, 36U)
  for i, byte in b"wght" {
    stat[20 + i] = byte
  }
  for i, byte in b"ital" {
    stat[28 + i] = byte
  }
  set_u16(stat, 36, 4)
  set_u16(stat, 38, 16)
  set_u16(stat, 40, 1)
  set_u32(stat, 48, 400U << 16)
  set_u16(stat, 52, 1)
  set_u16(stat, 54, 1)
  let tables : Map[String, Bytes] = { "STAT": Bytes::from_array(stat[:]) }
  // Need full second value body; malformed input must reject before mutation.
  let rejected = try {
    update_stat(tables, { "wght": 650.0 })
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(tables["STAT"], Bytes::from_array(stat[:]))
  stat.push(0)
  stat.push(0)
  tables["STAT"] = Bytes::from_array(stat[:])
  update_stat(tables, { "wght": 650.0 })
  assert_eq(read_u16(tables["STAT"], 12), 1)
  let start = read_u32(tables["STAT"], 14)
  let value = start + read_u16(tables["STAT"], start)
  assert_eq(read_u16(tables["STAT"], value + 2), 1)
}
