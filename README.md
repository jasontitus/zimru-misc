# zimru-misc

Auxiliary tooling for [zimru](https://github.com/jasontitus/zimru) that
**cannot live in zimru's clean-room MIT tree** — chiefly a GPL libzim
benchmark baseline. Kept here so neither `zimru` nor the `streetzim` app repo
is polluted. **GPL-3.0-or-later** — see [`LICENSE`](LICENSE), and
[`NOTICE.md`](NOTICE.md) for the license boundary and why it is version 3.

## `bench/` — zimru + xapianbuilder vs libzim

Benchmarks a full ZIM **recreate** (read → index → compress → write) two ways:

- **zimru + xapianbuilder** — MIT zimru does the ZIM I/O; it spawns the
  GPL `xapianbuilder` helper as a separate process (JSONL in → glass DB out)
  to build the Xapian fulltext/title indexes. The GPL boundary is the
  process boundary.
- **libzim** — the "old fashioned" path: libzim's `Creator` with its
  in-process Xapian indexer (`configIndexing`), driven by the
  `zimrecreate_libzim` harness (a faithful copy of zim-tools `zimrecreate`).

### Methodology (why the numbers are honest)

- **Matched compression.** libzim hardcodes `ZSTD_initCStream(..., 19)`;
  zimru is set to the same via `ZSTD_CLEVEL=19`. Without this you measure
  zstd-3-vs-19, not the tools — at *default* settings zimru looks ~30× faster
  purely because it used to default to zstd 3. Always match the level.
- **Indexer isolated.** Each tool runs with and without the index (`-j`);
  the index-build cost is the difference, so it's not conflated with
  compression.
- **Index equivalence verified.** The `fulltext`/`title` glass-DB blob sizes
  are reported per run; xapianbuilder's output matches libzim's byte-for-byte
  in size, and fulltext queries return identical hit counts.
- **Cache-warming controlled.** The source is `cat`-warmed into page cache
  before *both* tools, so neither gets a first/second-mover advantage;
  interleaved repeat runs are flat (<3% spread), and an explicit `sync`
  after each run adds ~0.1 s — i.e. wall time already captures the writes.
  Net: these measure **compute** (decompress + index + recompress), and the
  comparison is symmetric.
- **Lossless verified.** Independently, every content entry's decompressed
  bytes were hashed across source/zimru/libzim outputs: all user content is
  byte-identical; only the rebuilt indexes/listings and metadata labels
  differ (expected).

### Results

These tables were measured against **libzim 9.7.0**. The build script now pins
9.8.2 by default (`./bench/build-baseline.sh 9.7.0` **in a fresh `BUILD`
dir** reproduces the older baseline — a reused one is refused, not rebuilt); the newer head-to-head against zim-tools 3.8.0 / libzim 9.8.2 is in
[`bench/results/`](bench/results/README.md).

Intel Xeon W-2295 (36 threads), 125 GB RAM, source on HDD + output in page
cache. Matched zstd 19. Real OpenStreetMap street ZIMs (tile-heavy).

**Full recreate (read + index + compress + write):**

| Source                | zimru + xapianbuilder | libzim 9.7.0     | speed | size  |
| --------------------- | --------------------- | ---------------- | ----- | ----- |
| DC — 10 MB / 1.3k     | 0.9 s / **9.9 MB**    | 0.9 s / 18.2 MB  | 1.0×  | 0.54× |
| Hawaii — 119 MB / 822k| **4.4 s / 117 MB**    | 9.5 s / 180 MB   | 2.16× | 0.65× |
| Baltics — 1.35 GB/847k| **84.1 s / 1396 MB**  | 157.2 s / 2101 MB| 1.87× | 0.66× |

**Indexer isolated** (Baltics; both produced the identical 29.2 MB fulltext
+ 37.7 MB title index):

| | build only (no index) | with index | index-build cost |
| --- | --- | --- | --- |
| libzim 9.7.0 (in-process)        | 134.6 s | 157.2 s | **22.6 s** |
| zimru + xapianbuilder (spawned)  |  75.9 s |  84.1 s |  **8.2 s** |

→ xapianbuilder builds the same indexes **~2.8× faster** despite the
process/IPC boundary, and the overall recreate is **~1.9× faster and ~34%
smaller** at matched compression. The size win is lossless: libzim re-inflates
already-compressed map tiles/fonts by re-running them through zstd 19, while
zimru preserves the source's raw media clusters.

### Reproduce

```sh
# 1. one-time: build the pinned libzim baseline (needs g++, meson, ninja,
#    libxapian-dev, libicu-dev; builds zstd+lzma+libzim from source).
#    Or ./bench/fetch-baseline.sh to download released binaries instead.
BUILD=/storage/you/zimru-misc-build ./bench/build-baseline.sh

# 2. run the benchmark (RUNS=1 for very large archives)
PREFIX=$BUILD/prefix LIBZIM=$BUILD/zimrecreate_libzim \
ZIMRU=/path/to/zimru/target/release/zimrecreate \
XAPIANBUILDER=/path/to/xapianbuilder \
PY=/path/to/python-with-libzim \
RUNS=2 ./bench/bench.sh source-small.zim source-medium.zim
```

`zimru` must be built with the writer feature (`cargo build --release
--features writer`) so the index helper is compiled in, and `xapianbuilder`
must be on `$PATH` / `$XAPIANBUILDER` — zimru silently skips the indexes
without it, so `bench.sh` refuses to start if it cannot find one.

`bench/zim-manifest.cpp` is the libzim-backed content manifest used by
zimru's `bench/content-verify.sh`:

```sh
g++ -O2 -std=c++17 bench/zim-manifest.cpp -o bench/zim-manifest \
  $(pkg-config --cflags --libs libzim libcrypto)
```

## Tests

```sh
./tests/run.sh                      # lint + harness behaviour, no network
TEST_ZIM=small.zim ./tests/run.sh   # also build both C++ tools against the
                                    # installed libzim and round-trip that file
```

The behaviour tests drive the real `bench.sh` with stub tools: a source path
containing a quote is never executed as Python; a crashed run, a run that
writes nothing (on any repeat, not just the first), and a "+index" row whose
output has no index are each a FAILED row and a nonzero exit; and
`build-baseline.sh` refuses a reused checkout that is not the pinned tag and
commit. CI runs the first form only — the C++ round-trip needs a ZIM, and none
is committed here.
