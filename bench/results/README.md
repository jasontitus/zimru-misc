# Head-to-head: zimru + xapianbuilder vs zim-tools 3.8.0 / libzim 9.8.2

Raw output from a benchmark run on 2026-08-21. **Partial — the two largest
archives (Thai 1.3 GB, Chinese 3.1 GB) were still running when this was
written.** The files here are the harnesses' verbatim stdout, kept so the
numbers quoted anywhere else can be traced back to a run.

## Upstream under test

| component | version | source |
|---|---|---|
| zim-tools | 3.8.0 | `download.openzim.org/release/zim-tools/zim-tools_linux-x86_64-3.8.0.tar.gz` |
| libzim | 9.8.2 | bundled in the above; headers + `.so` from `libzim_linux-x86_64-9.8.2.tar.gz` |

Previous runs in this repo were against zim-tools 3.6.0 / libzim 9.3.0–9.7.0.
Numbers are not comparable across that boundary: 3.8.0 changed zimcheck's
report format and added an `M/Counter` regex check that most published
archives fail.

## Corpus

Twelve Wikipedia archives, 13 MB – 3.1 GB, chosen to cover scripts with
different tokenisation behaviour rather than just different sizes: CJK
(zh, ja, ko, yue — n-gram segmentation), abugida (hi, ta), RTL (ar, he),
no-word-spacing (th), Cyrillic (ba), Latin (en).

## Methodology

- **Matched compression.** Upstream's `zimrecreate` exposes no compression
  knobs and uses libzim's default (zstd 19), so zimru is driven at
  `--compression zstd --compression-level 19`. Comparing against zimru's
  own default (zstd 3) measures preset choice, not implementation.
- **ABBA ordering.** Each pair runs zimru, upstream, upstream, zimru, and
  each tool keeps its best. Before every run the previous output is
  removed, the source is re-read into page cache, and the previous run's
  writes are synced. See `creation-a-first-superseded.txt` for what this
  replaced and why.
- **Like-for-like index building.** Both modes produce the same entry set:
  `index` builds fulltext + title on both sides, `noft` passes `-j` to
  both, which drops the fulltext index and keeps the title index.
- **Every output is verified, not just timed.** `CHECK ==src` means
  upstream `zimcheck -A` found no error class in our output that the
  source did not already have. `SEARCH == OK` means upstream `zimsearch`
  returned the same top hit from the xapianbuilder-built index as from
  libzim's original.

## Two corrections made during the run

Both inflated zimru's numbers, and both are worth stating plainly because
the uncorrected figures circulated before they were caught.

1. **Ordering bias.** The harness ran zimru first, then upstream, warming
   the source once before the pair. zimru's output writes — up to a
   gigabyte — evicted the warmed source, so upstream re-read from disk
   what zimru got from cache. Worth a few percent, in zimru's favour, on
   exactly the comparison the benchmark exists to make. Fixed by the ABBA
   scheme above; the superseded numbers are kept for comparison.

2. **`-j` meant different things to the two tools.** Upstream's
   `--withoutFTIndex` drops only the fulltext index and still builds
   `X/title/xapian`; zimru's dropped both. The "noindex" mode therefore
   compared an archive with a title index against one without, and
   reported the missing index as a compression win — **-42.4% on Korean,
   where the honest figure is -4.7%**. Fixed in zimru (`-j` now matches
   upstream, `--without-indexes` drops both).

## What the corrected numbers say

zimru is faster on every row measured so far, by 1.15×–1.84×. The margin
tracks how much indexing the archive needs: widest on CJK (1.45×–1.84×),
narrowest on `en_100` (1.15×), which is mostly media with a 3.2 MB index.

Output sizes land within ±5%. Where zimru is smaller it is the *index*
that is smaller, not the content compression — content clusters agree
within 0.2%, which is what should happen when both tools run zstd 19 over
identical bytes.

Indic archives are disproportionately expensive on **both** sides — Tamil
takes 91 s for 134 MB against English's 9 s for 318 MB — which is a
property of the shared Xapian accent/stemming pipeline, not of either
writer.

## Content equivalence

`zimru/bench/content-verify.sh` diffs per-entry content manifests between
the source, zimru's recreate and upstream's, reading every entry through
**real libzim** (`../zim-manifest`) rather than through zimru's own reader.

| archive | entries | identical | changed | missing | extra |
|---|---|---|---|---|---|
| `wikipedia_zh_chemistry_mini` | 12 692 | 12 692 | 0 | 0 | 0 |
| `wikipedia_ko_top_mini` | 252 234 | 252 234 | 0 | 0 | 0 |

Both writers, both archives. The Korean file is the one where
`zimdump dump`-based verification silently fails: it contains entries
named `%` and `$`, and upstream zimdump aborts on them after 24 of
252 234 entries while still exiting 0.

## Files

| file | contents |
|---|---|
| `creation-abba-phase1.txt` | corrected creation benchmark, archives up to 318 MB |
| `creation-abba-phase1-runtimes.log` | every individual run time behind those rows |
| `creation-a-first-superseded.txt` | the biased A-first run, kept for comparison |
| `parity-*.log` | `zimru/bench/parity.sh` output, one per archive |

## Parity

`zimru/bench/parity.sh` runs 12 CLI invocations against each archive with
both binaries and diffs the output. This is a correctness harness, not a
benchmark — no timing is involved. **12/12 on 8 archives** (ar, ba, en,
ja, ko, ta, zh ×2), against 0/12 when first pointed at 3.8.0.
