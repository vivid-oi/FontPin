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

Use the designer's named styles without looking up axis coordinates:

```sh
moon run --target wasm src/command -- presets fixtures/robotomono/RobotoMono.ttf
moon run --target wasm src/command -- named fixtures/robotomono/RobotoMono.ttf RobotoMonoBold.ttf 6
```

For this pinned fixture, index 0 is Regular (400) and index 6 is Bold (700). Catalog indices are local to the source font. The library exposes `Font::named_instances()` and `instantiate_named(index)`; named conversion follows the existing deterministic coordinate-based output naming policy.

Build an application's font bundle in one operation:

```sh
moon run --target wasm src/command -- batch fixtures/robotomono/RobotoMono.ttf app-fonts examples/app-fonts.json
```

The example creates `regular.ttf`, `semibold.ttf`, `bold.ttf` and `manifest.json` inside a new `app-fonts` directory. Every font is validated and converted before publishing the directory. Existing directories, including empty ones, and files are refused. The destination must end in a new directory name without a trailing separator. Publication uses a sibling staging directory and one no-replace rename; forced termination may leave an orphan `.pending` directory.

```json
{"version":1,"outputs":[
  {"file":"regular.ttf","coordinates":{"wght":400}},
  {"file":"bold.ttf","preset":6}
]}
```

Each output selects exactly one coordinate object or named preset index from the same source font. Unknown fields and duplicate JSON keys are errors. Files use portable ASCII stems and `.ttf`; paths, device names and filenames differing only by ASCII case are refused. Manifests permit 1–16 outputs and are limited to 64 KiB by the CLI. The library's `BatchPlan::parse`, `to_json`, `filenames` and `Font::instantiate_batch` also work without filesystem access.

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

- Single TrueType sfnt fonts: `fvar`, `avar` 1.0, `gvar` tuple/point/delta decoding, IUP interpolation, simple outlines, XY-positioned and contour-point-aligned composite glyphs, and phantom-point metrics. Point alignment supports transformed and nested components and preserves unsigned point arguments.
- HVAR item variation stores and advance/left/right-bearing maps. Metrics use original values and final outline widths to avoid double application. Right-only maps derive left bearings; conflicting left/right maps are refused after combined rounding.
- MVAR global metrics: line, cap/x-height, sub/superscript, strike/underline and horizontal caret metrics, plus validated gasp thresholds. Originally identical OS/2 and hhea line metrics stay synchronized; intentionally different line metrics remain different.
- GDEF ligature caret instancing: evaluate VariationIndex coordinates, preserve glyph/mark classes, attachment points, point-index carets, mark-filtering sets and ordinary Device adjustments. GDEF is downgraded after its variation store is fully consumed. Fonts sharing that store with GPOS remain refused until positioning instancing is supported.
- cvar control-value freezing: interpolate CVT deltas at the pinned position, round once after accumulation and retain hint programs. Shared/private sparse CVT references and repeated references are handled without glyph IUP interpolation.
- Vertical TrueType metrics: `vhea` 1.0/1.1 and compressed `vmtx`, gvar top/bottom phantom interpolation, final top bearings and rebuilt vertical summary fields. MVAR vertical line/caret metrics participate in the same conversion.
- VVAR 1.0 advance, top and bottom bearing maps, including implicit advance indices and original-metric baselines. Derived bearings are combined before rounding; contradictory maps fail instead of losing a requested metric.
- Multilingual names: preserve format-1 UTF-16 language tags and their numeric associations, and retain validated Apple `ltag` tables byte for byte. Rewritten Unicode names retain localized prefixes; unsupported legacy encodings fail explicitly.
- Named fvar instances: validated positions/name IDs/flags, readable Unicode labels, source-record indices and optional PostScript name IDs. The default is first, synthesized only when absent. Catalog coordinates are detached; explicit fvar records remain visible, including duplicates.
- Batch asset plans: canonical manifest round trips, validated selections, deterministic filename order, aggregate output-byte limits and no partial artifact list on failure. The CLI publishes a complete directory with a matching manifest/report.
- Rebuilt `glyf`, long `loca`, `hmtx`, bounding boxes and horizontal summary metrics; updated OS/2 average width, weight/width/style flags, `post` slant and instance names. Copyright, family and license names are retained.
- STAT 1.0–1.2 value filtering, including preservation of static axes absent from `fvar`; preserved static layout tables; sorted output, checked offsets, table checksums and whole-font checksum.
- Bounded input/output sizes, axis/table counts, glyph and variation work. Limits are operation budgets, not a runtime deadline. Defaults: library 32 MiB, CLI 32,000,000 bytes, work 20 million.

This version deliberately rejects CFF/CFF2, WOFF/WOFF2, collections, partial axis pinning, avar 2, TrueType VVAR vertical-origin maps, composite alignment to phantom/unavailable points, variable GDEF/GPOS/GSUB layout, signatures and unknown tables. Unsupported data is never silently discarded. Axis-dependent TrueType hint instructions (`GETVARIATION`/`GETDATA`) are refused; retained instructions are not executed or certified by FontPin. Container validation is not a complete font sanitizer.

Named catalogs are bounded to 1,023 fvar records and 4,096 encoded bytes per selected label. Labels prefer US-English Windows Unicode, Unicode-platform, other Windows Unicode, then ASCII Mac Roman. Unsupported label encodings fail explicitly; this does not restrict the existing coordinate-based conversion API.

Style flags use weight class ≥700 for bold, `ital` ≥0.5 for italic or nonzero `slnt` when no italic axis exists. Regular is set only when neither applies. This explicit policy can differ from fontTools retaining source style flags.

Core library: Wasm, Wasm-GC, JavaScript and native. File CLI: Wasm and native, using `moonbitlang/async`. CI runs native tests and the complete file workflow on Linux, macOS and Windows. [Validation](docs/validation.md) explains exact coverage and independent fontTools comparisons.

Batch defaults allow 64 MiB of retained font outputs, 32 MiB per font, and the usual 20-million operation budget per font phase. The total-byte budget excludes the small report and is not a peak-memory guarantee or shared CPU deadline. Library plan text is bounded to 65,536 UTF-16 code units. Filesystems must support same-filesystem no-replace directory renaming; unsupported systems fail explicitly. Atomic visibility does not promise power-loss durability.

## Development and direction

```sh
moon run checks/gate.mbtx -- wasm moon
moon run checks/gate.mbtx -- wasm-gc moon
moon run checks/gate.mbtx -- js moon
moon run checks/gate.mbtx -- native moon
```

Outline, horizontal/vertical (including VVAR), MVAR global-metric, cvar control-value and multilingual-name instancing are implemented, together with named-style selection and batch asset publication. Roboto Mono supplies real-font outline/HVAR, named-style and batch-workflow evidence. Repository-authored probes supply MVAR/cvar, vertical-metric and language-metadata evidence. The intact upstream fontTools fixture is refused because its MVAR records are not in required tag order. Variable layout, partial instancing, CFF2 and subsetting remain future work; no compatibility claim is made for those inputs.

Font algorithms and new source files are MIT licensed; the adapted file-publication routine retains Apache-2.0. This is a complementary font transformation library, informed by the OpenType specification and checked against fontTools, rather than a port of a renderer or subsetter. See [design and use cases](docs/design.md), [sources and licenses](THIRD_PARTY.md), and [font corpus provenance](fixtures/README.md). Ecosystem uniqueness and performance advantages have not been established.
