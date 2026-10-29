# Sources and licenses

The implementation is written for this project against the specifications below. It is not a line-by-line port of fontTools. No implementation source from another font library was copied. Algorithm descriptions, interoperability behavior and independent references must not be confused with a claim of algorithmic novelty.

| Resource | Role | License / terms |
| --- | --- | --- |
| [Microsoft OpenType specification](https://learn.microsoft.com/en-us/typography/opentype/spec/) | Format and correctness requirements: sfnt, glyf, gvar, fvar, avar, HVAR, STAT and TrueType instructions | Microsoft documentation; linked as a reference, text not redistributed |
| [Common variation formats](https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats) | Tuple/point/delta formats, including cumulative repeated point indices | Same documentation terms |
| [FreeType 2.14.1 hint interpreter](https://github.com/freetype/freetype/blob/VER-2-14-1/src/truetype/ttinterp.c) | Behavior reference for refusing variable-only GETDATA/GETVARIATION instructions | FreeType License / GPLv2; linked, no implementation copied |
| [fontTools](https://github.com/fonttools/fonttools), version 4.67.0 | External executable oracle for instancing and decoded TTX comparisons; not a runtime dependency | MIT; not bundled as implementation code |
| [moonbitlang/core](https://github.com/moonbitlang/core) | MoonBit standard library | Apache-2.0 |
| [moonbitlang/async](https://github.com/moonbitlang/async), 0.22.5 | File/stdio/process support for CLI and checks | Apache-2.0 |
| [Roboto Mono and Roboto Slab](fixtures/README.md) | Unmodified real font fixtures, respectively positive and negative conversion cases | SIL OFL 1.1 and Apache-2.0; full licenses adjacent to fonts |

Unit test fixtures are constructed within the tests to exercise binary boundaries and variation algorithms. The fontTools process is an oracle, not proof of specification compliance in every case: for example, repeated packed-point indices have a dedicated specification-based regression test rather than relying on an upstream implementation's treatment.

`fixtures/metrics/MetricProbe.ttx` is a small synthetic font constructed for this project under the repository's MIT license. Its three glyphs and variation data were not copied from a production font. It checks MVAR line-height, cap-height and underline changes against fontTools; it is not evidence of broad production-font coverage for MVAR.

`fixtures/hints/CVTProbe.ttx` is a repository-authored synthetic font derived from MetricProbe under the same MIT license. Its two-axis control-value variations and nonempty hint programs support cvar differential tests. This is not a production font or a rasterization correctness claim.

`fixtures/vertical/VerticalProbe.ttx` is a repository-authored MIT synthetic font derived from CVTProbe. Its top/bottom phantom deltas and MVAR vertical ascent test vertical instancing; it is not a production CJK family. The format reference is Microsoft's [vhea specification](https://learn.microsoft.com/en-us/typography/opentype/spec/vhea), with fontTools 4.67.0 as the independent executable oracle.

`fixtures/vertical/VVARProbe.ttx` is derived from VerticalProbe under MIT, adding repository-authored VVAR rows and maps that match the existing phantom deltas. It checks the [OpenType VVAR specification](https://learn.microsoft.com/en-us/typography/opentype/spec/vvar); no upstream implementation or test data was copied. fontTools supplies the external comparison.

`fixtures/horizontal/HorizontalProbe.ttx` derives from VerticalProbe under MIT. Its repository-authored gvar/HVAR data exercise changing xMin and explicit left/right-bearing maps, following the [HVAR specification](https://learn.microsoft.com/en-us/typography/opentype/spec/hvar). fontTools 4.67.0 supplies the independent comparison; no implementation or production font data was copied.

`fixtures/names/LocalizedProbe.ttx` is a repository-authored MIT synthetic font derived from VerticalProbe, with Chinese Unicode names and an Apple language tag. It verifies name identity, family/license preservation and exact ltag retention with fontTools as decoder.

`fixtures/composites/AttachmentProbe.ttx` is a repository-authored MIT synthetic font derived from VerticalProbe, with two nested point-aligned composites and parent deltas that the specification requires ignoring on attached components. The [OpenType glyf specification](https://learn.microsoft.com/en-us/typography/opentype/spec/glyf) defines alignment order and argument types. fontTools 4.67.0 supplies a separate instancer/TTX comparison; a documented reference recompile resolves its fractional-offset bounding-box serialization difference. No implementation or upstream fixture was copied for these composites.

`fixtures/instancer/PartialInstancerTest-VF.ttx` is an unmodified upstream fontTools test fixture from commit `21b4060825fdb1259cf205208c49595b7cd670ec`; its full MIT license is adjacent. It is compiled intact as a rejection case: MVAR `hasc` follows `xhgt`, violating the required binary tag order. No table is removed and the implementation's validation is not weakened to force a positive result. Exact provenance and SHA-256 are recorded in `fixtures/README.md`.

Language metadata follows the [OpenType name specification](https://learn.microsoft.com/en-us/typography/opentype/spec/name) and [Apple ltag specification](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6ltag.html). These are documentation references; no text or implementation is copied. Format-1 unit fixtures are constructed in this repository under MIT. fontTools 4.67.0 does not implement format-1 language tags, so those tests check the specification's offsets, associations and byte preservation directly rather than claiming an independent format-1 oracle.

The command-line file-publication workflow in `src/command/files.mbt` was adapted for binary font output from the author's earlier [MBTRelMask](https://github.com/vivid-oi/MBTRelMask) project, which is Apache-2.0 licensed. That file retains Apache-2.0 licensing; the full license is in `LICENSES/Apache-2.0.txt`. The font algorithms and other new source files use this repository's MIT license.

All generated font outputs remain subject to their source font licenses. FontPin adds no branding, attribution string or watermark to font data; preserving upstream copyright and license records is intentional.

Named-instance enumeration follows the [OpenType fvar specification](https://learn.microsoft.com/en-us/typography/opentype/spec/fvar). `fixtures/presets/NamedProbe.ttx` is a repository-authored MIT derivative of CVTProbe. `src/presets_fixture_test.mbt` embeds its fontTools-compiled bytes solely for portable black-box tests, and `checks/embed_named_fixture.mbtx` reproduces those bytes. No external font implementation or named-instance test source was copied.

BatchPlan's schema, duplicate-key scan and portable filename validation are authored for this repository under MIT. The directory publisher in `src/command/batch.mbt` adapts the existing Apache-2.0 file-publication pattern and retains that license and SPDX notice. JSON syntax parsing uses Apache-2.0 `moonbitlang/core/json`; file creation, syncing and no-replace renaming use Apache-2.0 `moonbitlang/async`. No external batch tool or JSON parser implementation was copied. `examples/app-fonts.json` is a repository-authored MIT workflow example for the separately licensed Roboto Mono fixture.
