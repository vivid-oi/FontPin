# Font corpus

These are unmodified upstream binaries. Fonts are not implementation code and retain their own licenses. Their source versions are fixed so a failed conversion can be reproduced without a private font collection.

| File | Upstream source | License | SHA-256 |
| --- | --- | --- | --- |
| `robotomono/RobotoMono.ttf` | [Google Fonts, `ofl/robotomono/RobotoMono[wght].ttf`, commit `aa24661a5ba24c8f8a550a16fb13198719fc2c23`](https://github.com/google/fonts/blob/aa24661a5ba24c8f8a550a16fb13198719fc2c23/ofl/robotomono/RobotoMono%5Bwght%5D.ttf) | SIL OFL 1.1, adjacent `OFL.txt` | `66a80e79d17e4c7cabd162e2916578a4cc08fd19eef6e2a643305eae9c567b2b` |
| `robotoslab/RobotoSlab.ttf` | [Google Fonts, `apache/robotoslab/RobotoSlab[wght].ttf`, commit `369504809965ab8a0e467ad1f2d00ea07eefe1d0`](https://github.com/google/fonts/blob/369504809965ab8a0e467ad1f2d00ea07eefe1d0/apache/robotoslab/RobotoSlab%5Bwght%5D.ttf) | Apache-2.0, adjacent `LICENSE.txt` | `786ae192477447d33c6672c3055fba7cbfe45184c9a79e77a14f15716ca05b16` |

Roboto Mono is a real one-axis family with `gvar`, `HVAR`, and `avar`, including simple and composite glyphs. It has no GDEF/GPOS variable positioning. The oracle workflow compares every glyph's decoded points, component transforms and horizontal metrics at several weight coordinates; it does not merely check the output file size.

Roboto Slab is deliberately a rejection fixture: its GDEF variation store and GPOS VariationIndex records require layout instancing, which the first release does not support. The test verifies refusal and absence of a published output. No unsupported table has been stripped to make this fixture pass.

Font binaries and license files were downloaded directly from the linked commits on 2026-10-29. The license-file SHA-256 values are `50ab8dd54680d3473f649c9db86fece88434d097c7834475c1c72d2f8c429215` (Roboto Mono OFL) and `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` (Roboto Slab Apache license).
