# Licensing / provenance

This repo is intentionally **separate from `zimru`**. `zimru` is clean-room
MIT — no GPL source read or copied. The benchmark baseline here is the
opposite: it deliberately links and mirrors GPL libzim, so it must not live
in `zimru`'s tree.

- **`bench/zimrecreate_libzim.cpp`** is **GPL-2.0-or-later**. It is a faithful
  re-implementation of zim-tools' `zimrecreate` (new-namespace path) and
  copies the small `CopyItem` / `ItemProvider` / `guess_is_front_article`
  helpers from zim-tools `src/tools.h` + `src/zimrecreate.cpp`
  (GPL-2.0-or-later). It exists only as the "old fashioned libzim" baseline
  to benchmark against; it is not part of any shipping product.
- **`bench/bench.sh`** and **`bench/build-baseline.sh`** are orchestration
  only (invoke binaries, no library code) — GPL-2.0-or-later to match.
- It links **libzim** (GPL-2.0-or-later) and **Xapian** (GPL-2.0-or-later).

Keep it that way: nothing here may be transcribed back into `zimru`.
