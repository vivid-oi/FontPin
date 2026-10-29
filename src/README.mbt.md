# Embed the instancer

The library takes bytes and returns bytes; callers choose their own file,
browser, build-cache or document integration. All omitted axes select defaults,
so this function produces a fully static font at the requested weight.

```mbt check
///|
fn static_weight(
  source : Bytes,
  weight : Double,
) -> Bytes raise @fontpin.FontError {
  let font = @fontpin.Font::parse(source)
  let instance = font.instantiate({ "wght": weight })
  instance.to_bytes()
}

///|
test "embedding callers can distinguish an unsupported font flavor" {
  let unsupported = try {
    ignore(static_weight(b"OTTO", 650.0))
    false
  } catch {
    @fontpin.Unsupported(_) => true
    _ => false
  }
  assert_true(unsupported)
}
```

Use `font.axes()` before choosing coordinates when processing an unknown family.
Catch `Invalid`, `Unsupported` and `Limit` to present the appropriate diagnostic;
do not publish an output when conversion fails. The real-font command-line
workflow in the repository README supplies a complete file-to-file example.
