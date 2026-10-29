# Font corpus

The two TTF files below are unmodified upstream binaries. Fonts retain their own licenses. Their source versions are fixed so a failed conversion can be reproduced without a private font collection. Additional synthetic probes are described separately.

| File | Upstream source | License | SHA-256 |
| --- | --- | --- | --- |
| `robotomono/RobotoMono.ttf` | [Google Fonts, `ofl/robotomono/RobotoMono[wght].ttf`, commit `aa24661a5ba24c8f8a550a16fb13198719fc2c23`](https://github.com/google/fonts/blob/aa24661a5ba24c8f8a550a16fb13198719fc2c23/ofl/robotomono/RobotoMono%5Bwght%5D.ttf) | SIL OFL 1.1, adjacent `OFL.txt` | `66a80e79d17e4c7cabd162e2916578a4cc08fd19eef6e2a643305eae9c567b2b` |
| `robotoslab/RobotoSlab.ttf` | [Google Fonts, `apache/robotoslab/RobotoSlab[wght].ttf`, commit `369504809965ab8a0e467ad1f2d00ea07eefe1d0`](https://github.com/google/fonts/blob/369504809965ab8a0e467ad1f2d00ea07eefe1d0/apache/robotoslab/RobotoSlab%5Bwght%5D.ttf) | Apache-2.0, adjacent `LICENSE.txt` | `786ae192477447d33c6672c3055fba7cbfe45184c9a79e77a14f15716ca05b16` |

Roboto Mono is a real one-axis family with `gvar`, `HVAR`, and `avar`, including simple and composite glyphs. It has no GDEF/GPOS variable positioning. The oracle workflow compares every glyph's decoded points, component transforms and horizontal metrics at several weight coordinates; it does not merely check the output file size.

Roboto Slab is deliberately a rejection fixture: its GDEF variation store and GPOS VariationIndex records require layout instancing, which the first release does not support. The test verifies refusal and absence of a published output. No unsupported table has been stripped to make this fixture pass.

Font binaries and license files were downloaded directly from the linked commits on 2026-10-29. The license-file SHA-256 values are `50ab8dd54680d3473f649c9db86fece88434d097c7834475c1c72d2f8c429215` (Roboto Mono OFL) and `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` (Roboto Slab Apache license).

## Synthetic global-metric probe

`metrics/MetricProbe.ttx` is a small test font authored for this repository and covered by the root MIT license. It is not a production typeface or a modified copy of Roboto Mono. The XML is the input format of the official [fontTools TTX compiler](https://fonttools.readthedocs.io/en/latest/ttx.html); table meanings follow the [OpenType MVAR specification](https://learn.microsoft.com/en-us/typography/opentype/spec/mvar).

The font has three glyphs, one weight axis, a changing square outline, and four MVAR records (`cpht`, `hasc`, `hdsc`, `unds`) over positive and negative weight regions. It contains neither `cvar` nor variable layout. At weight 900 the declared global metrics must become ascender 780, descender -220, cap height 550, and underline thickness 52; the hhea ascender/descender also change because their original values match OS/2 typographic metrics. The differential script compares whole relevant tables with the upstream instancer and separately asserts those concrete values. The original XML is compiled to a temporary TTF during testing, so it can be reviewed without trusting a checked-in binary.

## Synthetic CVT and hint-program probe

`hints/CVTProbe.ttx` extends this repository's own MetricProbe under the root MIT license. It has weight and width axes, a non-linear `avar` map, `gvar`, `HVAR`, `MVAR`, and `cvar`. CVT tuples include positive, negative and cross-axis contributions. The five documented test locations exercise defaults, axis boundaries and interpolation. Its three small nonempty TrueType programs use PUSHB/POP; bytes `0x91` and `0x92` occur only as pushed operands. Tests compare every program byte against the compiled source and check that operand bytes are not mistaken for variable-only opcodes. This probe is synthetic and does not establish rasterizer compatibility or support for a production cvar family.

## Unmodified upstream instancing reference

`instancer/PartialInstancerTest-VF.ttx` is the unmodified four-glyph test fixture from [fontTools, commit `21b4060825fdb1259cf205208c49595b7cd670ec`](https://github.com/fonttools/fonttools/blob/21b4060825fdb1259cf205208c49595b7cd670ec/Tests/varLib/instancer/data/PartialInstancerTest-VF.ttx). Its SHA-256 is `5fe785f4f13d5cb65c7f9ada9fbff7cab47794828ea4f1f963c2a57f49d654c9`, matching the original LF bytes (Git blob `cee188460c00e4fca83d17dafcdaa78157aa0881`). The adjacent `instancer/LICENSE` preserves the exact upstream MIT license (Git blob `cc633905d333c4b42c1a0c8b34e9f734adeb6e1e`, SHA-256 `6787208f83f659ccbc2223b2fde952ffa6f7e8aca62f1a8a2bf5bc51bb1b2383`).

This upstream synthetic font contains `cvar`, vertical metrics, `ltag` and other variations. It has noncanonical MVAR ordering (`hasc` after `xhgt`). `checks/hints_oracle.mbtx` compiles the complete XML and verifies refusal for that precise reason without publishing output. No table is removed to manufacture success. It remains rejection evidence, not positive compatibility evidence.

## Vertical metric probe

`vertical/VerticalProbe.ttx` is authored in this repository under MIT, derived from `hints/CVTProbe.ttx`. Its three glyphs, two axes, top/bottom phantom deltas and vertical MVAR ascent are synthetic. No upstream production outline or fixture was copied into this probe. See `checks/vertical_oracle.mbtx` for five fontTools comparisons.

`vertical/VVARProbe.ttx` derives from VerticalProbe under the same MIT license. It adds two-region VVAR maps: A's advance deltas `[80,-30]`, top-bearing deltas `[-10,-20]` and bottom-bearing deltas `[50,-10]`. The repeated zero row covers the empty glyphs. These agree with its gvar phantom/outline variations, allowing a meaningful fontTools comparison; separate unit inputs intentionally disagree to test refusal.

## Horizontal metric probe

`horizontal/HorizontalProbe.ttx` is a repository-authored MIT derivative of VerticalProbe, adding changing xMin and HVAR left/right maps. A's left delta is `[10,0]` and right delta `[0,-10]` in positive weight/negative width regions. Five instanced fonts are compared with fontTools, with independent A `(advance,lsb)` expectations `(600,0)`, `(590,0)`, `(610,8)`, `(620,10)`, `(610,10)`. This is synthetic horizontal-map evidence.

## Localized name probe

`names/LocalizedProbe.ttx` is authored in this repository under MIT, derived from VerticalProbe. It adds Chinese family/full/license names and `ltag` language `zh-Hant`. The names workflow checks every numeric record identity, localized full-name prefixes, unchanged family/license values and exact language-table bytes at four weights. Format-1 language strings are separately constructed in unit tests.

## Named-instance probe

`presets/NamedProbe.ttx` derives from this repository's MIT CVTProbe. It defines three two-axis named records, with the default deliberately second in fvar order. The portable black-box fixture in `src/presets_fixture_test.mbt` is compiled with fontTools 4.67.0, preserving the fixed source timestamp. Regenerate it with `moon run checks/embed_named_fixture.mbtx -- python`, then `moon fmt`. It is synthetic; `checks/presets_workflow.mbtx` separately verifies all seven presets of the unmodified Roboto Mono production font.

## Point-aligned composite probe

`composites/AttachmentProbe.ttx` is authored in this repository under MIT, derived from VerticalProbe. It adds `joined` and `nested` components (five glyphs total), contour-point attachments, scaling, nested contour indices and nonempty composite instructions. Parent gvar deltas on the attached component are deliberately nonzero (`123,-77`) to verify the specification's ignore rule. The XY-positioned sibling has deltas `(10,-5)`, deliberately producing fractional component offsets at the intermediate coordinate. The reference comparison retains this case; see the bounding-box treatment in `docs/validation.md`.
