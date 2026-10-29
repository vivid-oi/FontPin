///|
test "public errors expose actionable categories" {
  let error : @fontpin.FontError = @fontpin.Unsupported("CFF2 outlines")
  assert_eq(error.message(), "unsupported font: CFF2 outlines")
  let rejected = try {
    ignore(@fontpin.Font::parse(b""))
    false
  } catch {
    @fontpin.Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}
