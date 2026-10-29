# Design boundary

FontPin takes a variable TrueType font and a complete design position and produces a static TrueType font that an existing consumer can use. Missing coordinates select defaults. The output is a real font containing instantiated outlines and metrics, not a coordinate wrapper around a variable font.

## Three end-to-end uses

1. **PDF export:** a MoonBit document generator receives a licensed variable TTF and a requested weight. It inspects axes, pins the requested weight, and passes static bytes to its existing TrueType embedder. It can cache bytes for repeated exports. FontPin does not provide a PDF writer or shaping engine.
2. **Application assets:** a desktop application's build job pins supported weights from one upstream family, checks all outputs and packages those files. Repeating the same build produces the same bytes. Unsupported layout tables stop the job before publishing a misleading font. The application decides whether reduced platform support or using the original variable font is appropriate.
3. **Font regression checks:** a font developer pins boundary/default/intermediate positions, compares glyph geometry and metrics against another instancer, and reloads each output as a static font. The supplied `.mbtx` workflow and fontTools oracle perform this process without private infrastructure.

## Small public contract

`Font::parse(Bytes)` creates an immutable parsed source; `axes()` returns a detached array. `Font::instantiate(Map[String, Double])` validates and builds a detached result. `Instance::to_bytes()` and `report_json()` expose the artifact and a compact summary. `inspect_font(Bytes)` serves both inputs and outputs. Typed errors make unsupported format features distinguishable from corrupt data and resource limits.

`named_instances()` returns detached fvar positions, resolved labels and source-record identities, with the default first. `instantiate_named(index)` selects from that catalog and uses the same conversion/limit contract as explicit coordinates. It does not replace the established coordinate-based output naming policy.

Every transformation occurs in local copies. A failed conversion leaves the source reusable. The command writes only after the library returns a complete, rechecked font. A sibling temporary file plus no-replace rename prevents a failed conversion or existing destination from becoming a partially published font; forced process termination can leave an orphan `.pending` file.

## Correctness choices

- Interpolate in normalized F2Dot14 design coordinates after `avar`; round with OpenType's `floor(x + 0.5)` rule.
- Decode shared/private tuple points and runs, accumulate repeated point references, interpolate untouched contour points with IUP and keep phantom points separate.
- Resolve composites with cycle, depth and work guards. Preserve glyph IDs, instructions, component transforms and all untouched tables.
- Resolve contour-point attachments against the already assembled parent points after transforming the varied child. Keep point indices unsigned, ignore XY-only rounding/offset flags for attachments, and ignore parent gvar deltas for point-aligned components as OpenType prescribes. Phantom-point attachment requires additional metric semantics and is explicitly refused.
- Use original horizontal metrics as the HVAR baseline, then recompute summary metrics from final outlines and advances.
- Use original vertical metrics as the VVAR baseline. Apply explicit top/bottom maps without adding phantom deltas twice; combine derived values before rounding, reject inconsistent final bearings and recompute vhea from final vmtx.
- Mark overlap consistently with the reference instancer. This does not geometrically remove overlaps.
- Rebuild canonical table order, lengths, alignment and checksums; parse the final container again. Unknown or unsupported semantics produce a diagnostic instead of a lossy result.

Checksums do not prove the validity of every preserved static table. FontPin is a bounded instancer for supported, structurally valid fonts, not an execution sandbox for hostile font bytecode or a replacement for a full sanitizer.

## Relationship to other projects

The reviewed MoonBit projects [mizchi/font](https://github.com/mizchi/font) and [bikallem/freetype](https://github.com/bikallem/freetype) cover parsing, drawing, subsetting or runtime rendering. The former exposes `glyph_outline_at`, `glyph_metrics_at` and `subset_font`; the latter is a pure MoonBit FreeType implementation. FontPin's boundary is static font-file construction, including coordinated variation removal and metric updates. Repository availability and scope can change; this is a scoped comparison, not proof that no competing implementation exists. Mooncakes coverage remains incomplete because browser access was unavailable during research.

Demand for the underlying workflow is evidenced by [fontTools' instancer](https://fonttools.readthedocs.io/en/latest/varLib/instancer.html) and [Google Fonts' gftools instancer](https://github.com/googlefonts/gftools/blob/main/Lib/gftools/instancer.py). Their existence supports the workflow, not an estimate of MoonBit-specific user adoption.
