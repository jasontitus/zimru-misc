# Licensing / provenance

This repository is **GPL-3.0-or-later**; [`LICENSE`](LICENSE) contains GPLv3.

It is intentionally **separate from `zimru`**. `zimru` is clean-room MIT — no
GPL source read or copied. The benchmark baseline here is the opposite: it
deliberately copies from and links GPL code, so it must not live in `zimru`'s
tree.

## Why GPL-3.0-or-later, and not GPL-2.0-or-later

The most restrictive input decides, and that is zim-tools:

| Input | Its licence | How it is used here |
| --- | --- | --- |
| [zim-tools](https://github.com/openzim/zim-tools) `src/zimrecreate.cpp`, `src/tools.h`, `src/tools.cpp` | **GPL-3.0-or-later** | source copied into `bench/zimrecreate_libzim.cpp` |
| [libzim](https://github.com/openzim/libzim) | GPL-2.0-or-later | linked by both C++ tools |
| Xapian (via libzim) | GPL-2.0-or-later | linked transitively |
| OpenSSL 3.x (`libcrypto`) | Apache-2.0 | linked by `bench/zim-manifest.cpp` for MD5 |
| ICU, zstd, liblzma (via libzim) | Unicode-3.0 / BSD-3-Clause / 0BSD–public domain | linked transitively; all permissive and GPL-compatible |

Code copied from a GPL-3.0-or-later work cannot be relicensed down to
GPL-2.0-or-later, so version 3 is the floor. The "or later" grants on libzim
and Xapian permit combining them under version 3, and Apache-2.0 is compatible
with GPLv3 (it is not compatible with GPLv2). GPL-3.0-or-later also matches
[`xapianbuilder`](https://github.com/jasontitus/xapianbuilder), the other GPL
side of the same boundary.

This repository distributes **source only**. If you distribute a built
`zim-manifest`, link it against OpenSSL 3.x: OpenSSL 1.1.1 and earlier are
under the OpenSSL/SSLeay licence, which is not GPL-compatible.

## Per file

- **`bench/zimrecreate_libzim.cpp`** — derived from zim-tools. It re-implements
  `zimrecreate` (new-namespace path) and copies the small `CopyItem` /
  `ItemProvider` / `guess_is_front_article` helpers. The upstream copyright
  lines and licence notice are reproduced in the file header. It exists only as the "old
  fashioned libzim" baseline to benchmark against; it is not part of any
  shipping product.
- **`bench/zim-manifest.cpp`** — original work, GPL because it links libzim.
- **`bench/*.sh`** — original orchestration (invoke binaries, no library
  code); GPL-3.0-or-later to match the rest of the repository.
- **`bench/results/`** — recorded benchmark output: timings and archive names
  only, no third-party content.

## The boundary with zimru

`zimru` never links anything in this repository or in `xapianbuilder`. It
spawns `xapianbuilder` as a separate program and exchanges data with it
(JSONL in, a Xapian database out); the tools here are only ever run from
benchmark scripts. Whether a given downstream distribution of those programs
together is "mere aggregation" depends on that distribution, not just on the
process boundary — see the
[FSF's guidance](https://www.gnu.org/licenses/gpl-faq.html#MereAggregation).
This is not legal advice.

Keep it that way: nothing here may be transcribed back into `zimru`.
