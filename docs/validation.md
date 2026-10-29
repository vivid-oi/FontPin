# Reproduce the checks

Run from the repository root with MoonBit `0.10.17+d971670cd` (stable toolchain checked on 2026-10-29) and Node.js 22 or newer for JavaScript tests. CI pins the toolchain and core to that version through the MIT-licensed [setup-moonbit action](https://github.com/hustcer/setup-moonbit/tree/v1.22):

```
moon update
moon run checks/gate.mbtx -- wasm moon
moon run checks/gate.mbtx -- wasm-gc moon
moon run checks/gate.mbtx -- js moon
moon run checks/gate.mbtx -- native moon
```

Native tests execute the compiled code and the file CLI. They require a working host C toolchain; Windows uses the Visual Studio developer environment. A successful `moon check --target native` alone is not a native execution result.

The gate checks formatting, regenerated public interfaces, strict compilation, build and tests. Wasm and native also run the real-file workflow in `checks/workflow.mbtx`: conversion, output reload, byte-for-byte determinism, no-clobber publication, invalid coordinates, unsupported variable layout, truncated input, and recovery after refusal.

Wasm and native additionally run `checks/presets_workflow.mbtx`: enumerate all seven Roboto Mono styles, check their expected labels/weights, export each by catalog index and compare its bytes with explicit coordinate conversion. Every output is reloaded; invalid/out-of-range selectors, existing destinations, source preservation and recovery are checked. The same workflow runs as part of actual native execution on Linux, macOS and Windows.

Portable named-instance tests use the repository-authored `NamedProbe.ttx` compiled into test-only bytes. They check default ordering, source indices, two-axis positions, optional PostScript IDs, detached maps, coordinate-equivalent output, static reload and limits. White-box cases cover omitted default records, invalid reserved flags and references, non-default misuse of IDs 2/17/6, out-of-range coordinates, UTF-16 pairs, malformed strings and catalog limits. No named-style performance claim is made.

The gate also runs `checks/batch_workflow.mbtx` on Wasm and native. It consumes `examples/app-fonts.json` and the unmodified Roboto Mono font, compares each of three outputs with single-font conversion and reloads them. Two independent bundle builds must have identical fonts and persisted reports. Invalid final requests, unknown presets, path traversal, duplicate keys, malformed UTF-8, oversized plan files, existing files, existing empty/nonempty directories and missing parents must publish no partial bundle. Failed publication must leave no staging directory, and a subsequent valid batch must succeed without changing its source. CI executes this directory-publication workflow on Linux, macOS and Windows.

Portable batch tests cover canonical parse/serialize/reparse, reordered inputs, independent snapshots, escaped duplicate keys at multiple depths, device/path/case filename conflicts, exact filename and manifest size limits, output-count and selector limits, finite numeric coordinates, static reload, single-conversion equivalence, aggregate output-byte boundaries, validation-before-instancing and recovery. The pinned standard JSON parser normally accepts duplicate keys, so BatchPlan adds a syntax-checked token scan with decoded key comparison rather than silently retaining a replacement value.

Standalone `.mbtx` scripts resolve their own dependencies. Each explicitly pins async `0.22.5`, matching `moon.mod`; unversioned script imports can select a newer release incompatible with the pinned compiler even when the project dependency is fixed.

Each oracle first builds the project for its requested target, resolving the pinned project dependencies in a fresh clone, before invoking the CLI with `--frozen`. `moon update` updates the registry index and does not by itself populate the project's dependency directory.

## Independent implementation comparison

The oracle is a test dependency, not a FontPin runtime dependency:

```
python -m pip install fonttools==4.67.0
moon run checks/oracle.mbtx -- wasm moon python
moon run checks/oracle.mbtx -- native moon python
moon run checks/variation_oracle.mbtx -- wasm moon python
moon run checks/hints_oracle.mbtx -- wasm moon python
moon run checks/vertical_oracle.mbtx -- wasm moon python
moon run checks/vertical_oracle.mbtx -- wasm moon python fixtures/vertical/VVARProbe.ttx
moon run checks/vertical_oracle.mbtx -- wasm moon python fixtures/horizontal/HorizontalProbe.ttx
moon run checks/vertical_oracle.mbtx -- wasm moon python fixtures/composites/AttachmentProbe.ttx
moon run checks/names_oracle.mbtx -- wasm moon python
moon run checks/layout_oracle.mbtx -- wasm moon python
```

The script calls the upstream `fontTools.varLib.instancer` and `fontTools.ttx` command-line modules with fontTools' default overlap-flag handling. No local Python implementation or generated Python test script participates. It converts the unmodified Roboto Mono fixture at weights 100, 400, 650 and 700, independently checks the output sfnt directory and checksums, then compares every glyph's decoded points/components, glyph order, character map and horizontal metrics. The comparison ignores XML indentation and comments, not geometry or metric differences. Font names and timestamp bytes are not compared to fontTools because naming policy and serialization layout can differ without changing glyph semantics.

See [the corpus provenance](../fixtures/README.md) for exact source revisions, hashes and font licenses. Small synthetic inputs in unit tests exercise malformed structures and boundary conditions separately from the real-font differential.

The separate variation oracle compiles the repository-authored `MetricProbe.ttx` with the upstream TTX compiler and checks weights 100, 400, 650 and 900. It compares OS/2, hhea, post, glyf and hmtx XML against fontTools. The hhea `numberOfHMetrics` storage-compression field is excluded while every actual per-glyph advance and bearing is compared. OS/2 `fsSelection` receives a narrower check: the italic/bold/regular bits (`0x61`) must follow FontPin's documented style policy, and every other bit must match fontTools. At weight 900 FontPin sets bold (`32`); fontTools' default retains the source regular flag (`64`). No MVAR field is excluded. Independent expected-value assertions check positive, zero and negative MVAR deltas, including synchronized hhea ascent/descent. This is a synthetic global-metric test, not evidence for a production MVAR family.

The hints oracle compiles the repository-authored two-axis `CVTProbe.ttx` and compares CVT values, OS/2, hhea, post, glyf, hmtx, fpgm and prep with fontTools. It uses the same narrow hhea/fsSelection rules as the metric oracle. TTX `-i` dumps instructions as hex, so the test additionally compares every fpgm, prep and glyph-program byte against the uninstantiated source. It checks argument-order independence byte for byte. This verifies byte preservation and variation arithmetic; it does not run a hint interpreter or compare rasterized pixels.

| Weight | Width | Expected CVT values |
| --- | --- | --- |
| 400 | 100 | `[512, -300, 96, 240]` |
| 100 | 75 | `[512, -300, 80, 180]` |
| 650 | 87.5 | `[536, -300, 96, 210]` |
| 900 | 125 | `[536, -340, 96, 240]` |
| 900 | 75 | `[552, -300, 96, 180]` |

The intermediate case includes the `avar` weight mapping from normalized `0.5` to `0.75`, plus a cross-axis CVT tuple. The intact upstream reference remains a refusal case: its MVAR records have `hasc` after `xhgt`, contrary to the required binary tag order. The workflow checks this exact diagnostic and absence of output. It is not positive cvar evidence.

The vertical oracle compiles `fixtures/vertical/VerticalProbe.ttx`, retaining its gvar/HVAR/MVAR/cvar and hint programs. At five weight/width positions it compares every glyph outline, horizontal metric, vertical metric and vhea field with fontTools. Only `numberOfVMetrics`, a storage-compression count, is excluded; all advances and bearings are compared. Independent expected `(advanceHeight, topSideBearing)` for glyph A are `(1000,100)`, `(970,80)`, `(1045,83)`, `(1080,90)` and `(1050,70)`. This exercises avar, negative deltas and vertical MVAR ascent. A generated static output is reloaded with `inspect` after every conversion.

The same oracle accepts an optional fixture path. Its second CI invocation compiles `VVARProbe.ttx`, which has matching gvar and VVAR data, and checks the same five positions. VVAR must disappear from static output. This agrees with fontTools' full TrueType instancing while exercising FontPin's original-baseline map evaluation. Unit tests independently check implicit indices, bottom-only maps, unsigned/signed overflow, every table truncation, unsupported map/origin formats, work limits, complementary half-unit rounding, contradictory maps and recovery. If explicit top and bottom mappings produce different rounded top bearings after deriving from the final outline, FontPin refuses the position. This is a deliberate preservation boundary, not a claim to accept every VVAR font.

The horizontal-map invocation compiles `HorizontalProbe.ttx` at those same five positions. It compares every glyph and horizontal/vertical metric with fontTools while independently checking A's advances and left bearings. The left-bearing map changes xMin-related bearings, and the right-bearing map changes with width. Unit tests separately check right-only derivation, half-unit rounding before subtraction, contradictory maps, overflow, all table truncations, malformed offsets, evaluation work and recovery. Both explicit bearings must lead to the same rounded stored left bearing. For a manual example, compile this TTX and pin `wght=650 wdth=87.5`; A has advance 610 and left bearing 8.

To run this example manually, first compile the TTX with `python -m fontTools.ttx -o VerticalProbe.ttf fixtures/vertical/VerticalProbe.ttx`, then run `moon run --target wasm src/command -- instance VerticalProbe.ttf Vertical650.ttf wght=650 wdth=87.5`. Expected A metrics are height 1045 and top bearing 83. Unit tests separately cover fractional rounding, compressed metric storage, mismatched table pairs, truncation, invalid reserved fields and metric overflow. No pixel-rasterization claim is made.

The names workflow compiles `LocalizedProbe.ttx` intact, pins weights 100, 400, 650 and 900 at width 85, and decodes the static outputs with fontTools. Every name record key must survive, all family/license values must match, localized full-name prefixes must remain and the `ltag` table must be byte-exact. Each output is reloaded with `inspect`. To reproduce manually, compile `fixtures/names/LocalizedProbe.ttx` with the official TTX CLI, then call FontPin's `instance` command with `wght=650 wdth=85` and inspect the name/ltag tables with TTX.

Format-1 name language tags have separate specification-based binary tests: mixed language IDs, unchanged family/license records, complete original string-storage retention, rewritten style names, localized prefixes including surrogate pairs, invalid tag references, truncated/odd UTF-16, malformed offsets and unsupported legacy encodings. Apple `ltag` must retain its original bytes. Language-tag validation checks ASCII subtag shape and bounds; it does not consult the IANA registry. fontTools 4.67.0 does not support format-1 name language tags, so no fontTools agreement is claimed for that format.

The point-attachment invocation uses `AttachmentProbe.ttx` at the same five positions, comparing every outline record, component argument/transform, glyph program, hmtx/vmtx entry and vhea field. It preserves point-aligned components and tests nested attachments after leaf interpolation. Output reload and byte equality after reversing axis arguments run at every position. To reproduce manually, compile this TTX and pin `wght=650 wdth=87.5`; the output contains five glyphs and retains composite instructions and both attachments.

There is one explicit reference normalization for this fixture. fontTools 4.67.0 derives compound bounds before rounding fractional component offsets for serialization. At `(650,87.5)` its direct static output reports nested `xMax=800`, while recompiling that same static font through the official TTX CLI gives `xMax=801`, matching FontPin's bounds from serialized integer offsets. The oracle therefore recompiles only this reference static output before comparing bounds/summary metrics. It separately asserts that recompilation changes no contour/component/instruction record and no per-glyph horizontal or vertical metric. The fractional case remains in the corpus; no geometry is removed or excluded from the final comparison. The unnormalized bounding boxes are not claimed to match.

Attachment unit tests cover transform-before-alignment, XY flags ignored in point mode, byte/word unsigned arguments including 40000 and 65535, nested flattened point indexing, preserved instructions, prescribed parent-delta ignoring, unavailable/phantom points, resource limits and recovery. Existing cycle/depth tests remain active. Phantom-point alignment is explicitly unsupported.

## Scope of the evidence

The layout oracle compiles the full `CaretProbe.ttx`, freezes four positions and compares every decoded GDEF/GPOS/GSUB XML field with fontTools. It verifies independent caret values, source preservation, static reload, deterministic bytes and absence of active VariationIndex/store data. Unit inputs check every GDEF truncation, invalid coverage/classes/offsets, overflow, work/output limits, ordinary Device preservation and 16-bit relocation refusal. GDEF stores shared with GPOS are still refused at this milestone. FontPin freezes layout tables for downstream shapers; it does not shape text or compare pixels itself.

Passing these checks is evidence for the documented font/table subset and tested coordinates. It is not a claim that every OpenType font, shaping engine, pixel rasterizer or operating-system installer is compatible. In particular, variable GDEF/GPOS data must be refused until layout instancing is implemented; deleting it would invalidate the test's preservation contract.

GitHub Actions runs three portable core targets, actual native execution on Linux/macOS/Windows, and a separate fontTools differential. Consult the run attached to a specific commit for its result; this document describes the checks rather than asserting that an unfinished run passed.
