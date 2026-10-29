# FontPin

Freeze a variable TrueType font into a deterministic, standalone static `.ttf`, directly from MoonBit. The library operates on `Bytes`; the command line reads a font and publishes a new file. No Python, renderer or native font library is needed to perform a conversion.

FontPin is for application and document-tool developers who receive variable fonts but need fixed font assets: a PDF pipeline with a static-font embedder, a desktop application packaging a small set of approved styles, or a build job producing reproducible font resources. It preserves glyph IDs and character mappings; it does not subset fonts.

## Try it

Tested toolchain: MoonBit `0.10.17+d971670cd`, moon `0.1.20261023`. This repository uses `moon.mod` and `moon.pkg`.

```sh
moon update
moon run --target wasm src/command -- inspect fixtures/robotomono/RobotoMono.ttf
moon run --target wasm src/command -- instance fixtures/robotomono/RobotoMono.ttf RobotoMono650.ttf wght=650
moon run --target wasm src/command -- inspect RobotoMono650.ttf
```

The example uses the unmodified, licensed Roboto Mono variable font. The output has 1,006 glyphs and no variable outline/metric tables (`fvar`, `avar`, `gvar`, `HVAR`, `MVAR`, `cvar`). Omitted axes use their defaults. Coordinates must be finite, known and in range. Output paths must be new; conversion completes before a temporary file is synced and renamed without replacement. Failure returns a nonzero status and a diagnostic on stderr. Success writes JSON on stdout.

## Library

Import `"vivid-oi/fontpin" @fontpin` in your `moon.pkg`:

```moonbit
let font = @fontpin.Font::parse(input_bytes)
let axes = font.axes()
let instance = font.instantiate({ "wght": 650.0 })
let output_bytes = instance.to_bytes()
let report = instance.report_json()
```

`Font::parse` checks the sfnt container and reads axes; `instantiate` checks whether every table can safely participate in conversion. `inspect_font` accepts static and variable TTF files. Errors distinguish `Invalid`, `Unsupported` and `Limit`; `message()` provides an explanation. [Generated API](src/pkg.generated.mbti) lists the complete public surface; the [checked embedding example](src/README.mbt.md) is compiled with the tests.

## Implemented scope

- Single TrueType sfnt fonts: `fvar`, `avar` 1.0, `gvar` tuple/point/delta decoding, IUP interpolation, simple outlines and XY-positioned composite glyphs, and phantom-point metrics.
- HVAR item variation stores and advance/left-side-bearing maps. Metrics use the original values to avoid applying the same advance variation twice.
- MVAR global metrics: line, cap/x-height, sub/superscript, strike/underline and horizontal caret metrics, plus validated gasp thresholds. Originally identical OS/2 and hhea line metrics stay synchronized; intentionally different line metrics remain different.
- cvar control-value freezing: interpolate CVT deltas at the pinned position, round once after accumulation and retain hint programs. Shared/private sparse CVT references and repeated references are handled without glyph IUP interpolation.
- Rebuilt `glyf`, long `loca`, `hmtx`, bounding boxes and horizontal summary metrics; updated OS/2 average width, weight/width/style flags, `post` slant and instance names. Copyright, family and license names are retained.
- STAT 1.0–1.2 value filtering, including preservation of static axes absent from `fvar`; preserved static layout tables; sorted output, checked offsets, table checksums and whole-font checksum.
- Bounded input/output sizes, axis/table counts, glyph and variation work. Limits are operation budgets, not a runtime deadline. Defaults: library 32 MiB, CLI 32,000,000 bytes, work 20 million.

This version deliberately rejects CFF/CFF2, WOFF/WOFF2, collections, partial axis pinning, avar 2, VVAR and vertical-metric tables, point-matched composites, HVAR right-side-bearing maps, variable GDEF/GPOS/GSUB layout, signatures and unknown tables. Unsupported data is never silently discarded. Axis-dependent TrueType hint instructions (`GETVARIATION`/`GETDATA`) are refused; retained instructions are not executed or certified by FontPin. Container validation is not a complete font sanitizer.

Style flags use weight class ≥700 for bold, `ital` ≥0.5 for italic or nonzero `slnt` when no italic axis exists. Regular is set only when neither applies. This explicit policy can differ from fontTools retaining source style flags.

Core library: Wasm, Wasm-GC, JavaScript and native. File CLI: Wasm and native, using `moonbitlang/async`. CI runs native tests and the complete file workflow on Linux, macOS and Windows. [Validation](docs/validation.md) explains exact coverage and independent fontTools comparisons.

## Development and direction

```sh
moon run checks/gate.mbtx -- wasm moon
moon run checks/gate.mbtx -- wasm-gc moon
moon run checks/gate.mbtx -- js moon
moon run checks/gate.mbtx -- native moon
```

Outline, horizontal, MVAR global-metric and cvar control-value instancing are implemented. Roboto Mono supplies real-font outline/HVAR evidence; repository-authored synthetic fonts supply MVAR/cvar evidence. The unmodified upstream fontTools fixture contains unsupported vertical tables and serves as a rejection test. Variable layout, vertical metrics, partial instancing, CFF2 and subsetting remain future work; no compatibility claim is made for those inputs.

Font algorithms and new source files are MIT licensed; the adapted file-publication routine retains Apache-2.0. This is a complementary font transformation library, informed by the OpenType specification and checked against fontTools, rather than a port of a renderer or subsetter. See [design and use cases](docs/design.md), [sources and licenses](THIRD_PARTY.md), and [font corpus provenance](fixtures/README.md). Ecosystem uniqueness and performance advantages have not been established.
