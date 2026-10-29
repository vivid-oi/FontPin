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

The font designer's presets can be selected with `font.named_instances()` and
`font.instantiate_named(index)`. The catalog always places the default design
position at index zero. Returned coordinates are detached from the source font.

```mbt check
///|
fn designer_style(
  source : Bytes,
  index : Int32,
) -> Bytes raise @fontpin.FontError {
  @fontpin.Font::parse(source).instantiate_named(index).to_bytes()
}

///|
test "named selection propagates typed source errors" {
  assert_true(
    try {
      ignore(designer_style(b"OTTO", 0))
      false
    } catch {
      @fontpin.Unsupported(_) => true
      _ => false
    },
  )
}
```
