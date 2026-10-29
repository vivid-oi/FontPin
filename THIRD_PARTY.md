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

The command-line publication pattern uses the same documented `moonbitlang/async` file APIs as the author's earlier [MBTRelMask](https://github.com/vivid-oi/MBTRelMask) project. It was adapted for binary font output here; FontPin's font algorithms are separate. MBTRelMask is MIT licensed.

All generated font outputs remain subject to their source font licenses. FontPin adds no branding, attribution string or watermark to font data; preserving upstream copyright and license records is intentional.
