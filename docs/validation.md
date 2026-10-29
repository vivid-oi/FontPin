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

The intermediate case includes the `avar` weight mapping from normalized `0.5` to `0.75`, plus a cross-axis CVT tuple. The upstream `PartialInstancerTest-VF.ttx` is separately compiled intact as a rejection test for unsupported vertical metrics and language extensions. The only positive cvar font oracle in this release is the self-authored synthetic probe.

## Scope of the evidence

Passing these checks is evidence for the documented font/table subset and tested coordinates. It is not a claim that every OpenType font, shaping engine, pixel rasterizer or operating-system installer is compatible. In particular, variable GDEF/GPOS data must be refused until layout instancing is implemented; deleting it would invalidate the test's preservation contract.

GitHub Actions runs three portable core targets, actual native execution on Linux/macOS/Windows, and a separate fontTools differential. Consult the run attached to a specific commit for its result; this document describes the checks rather than asserting that an unfinished run passed.
