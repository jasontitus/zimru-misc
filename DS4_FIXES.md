# Disposition of the DS4 sweep — zimru-misc

Three findings: two about the benchmark baseline's supply chain, one
injection-class. All fixed.

| Finding | What was wrong | Fix |
|---|---|---|
| [medium] `bench/build-baseline.sh:46` | libzim was cloned from **unpinned git master** while the comment claimed "libzim 9.7.0". The baseline silently drifted to whatever upstream happened to be that day, which makes the apples-to-apples comparison mean something different from one run to the next — the one property a baseline exists to have. | Pinned: `git clone --branch "$LIBZIM_TAG"`, defaulting to 9.8.2 and overridable as `$1` or `$LIBZIM_TAG`. Comments now say pinned rather than naming a version the script did not fetch. The first version of this fix was a no-op on any reused `$BUILD`: the clone is skipped when `$SRC/libzim` exists, so a leftover master checkout was still built. `clone_pinned` now refuses to build unless the checkout is its own repository, its HEAD is the requested tag's commit, and no tracked file is modified or staged (zstd too). For zstd v1.5.6 and libzim 9.8.2 / 9.7.0 the commit SHA is recorded in the script and must match, which also catches a *moved* tag. **Any other libzim tag is pinned by name only** — the script prints a note — so there a local `git tag -f` would pass. Untracked files are deliberately not inspected: a real libzim build leaves meson's `subprojects/googletest-*` in the tree, and an attempt to refuse them broke every re-run (caught by running the real build on Linux, not by the stub tests). |
| [low] `bench/build-baseline.sh:35` | The xz 5.4.6 release tarball was fetched over TLS and built unverified. | `sha256sum -c` against a pinned digest, captured from the published artefact, on **every** run with a fresh extract — the first version skipped the check whenever an extracted `xz-5.4.6/` was already present. A failing tarball is deleted. The comment is explicit that pinning makes a *later* substitution detectable and is not a substitute for verifying the upstream signature when first adopting a version. |
| [low] `bench/bench.sh:64` | `$SRC` was interpolated into the source text of a `python -c` one-liner (`Archive('$SRC')`), so an archive path containing a quote broke the verification step or injected Python. An earlier revision of this table described a different problem (`timeit` swallowing exit status) and marked the row "superseded"; the interpolation itself was still there. | The path is passed as argv and read as `sys.argv[1]`, the way `idxcheck` in the same script already did. That was the only place a shell variable reached Python source; the remaining `awk "BEGIN{…$x…}"` sites take only `stat`/`date` output. |

## Fixed alongside

- `bench.sh` ran under `set -u` only; it is now `set -euo pipefail`, and the
  script exits nonzero if any row or any source failed.
- A run that exits 0 without producing output is a FAILED row. The output is
  removed and re-checked before/after **each** repeat: the first attempt at
  this checked once after the loop, so with the default `RUNS=2` a file from
  run 1 vouched for a no-op run 2, whose time then won "best".
- A "+index" row whose output has no title index — or no fulltext index when
  the source had one — is a FAILED row. `idxcheck` used to print the flags and
  return 0 whatever they said, which is exactly how a missing or broken
  `xapianbuilder` produces a fast-looking zimru row.
- `bench.sh` fell back to host-specific binary paths when `zimrecreate` /
  `xapianbuilder` were not on `$PATH`; it now stops with a clear error.
- Row labels said `libzim9.7.0` regardless of what was installed; they now
  report the version from the installed `libzim.pc`.
- The baseline is installed with `libdir=lib` and no longer assumes
  `x86_64-linux-gnu`; `fetch-baseline.sh` takes `ARCH=linux-aarch64`.

Each of the above is executed by `tests/run.sh`; the first-attempt mistakes
noted here were found by an adversarial review of the fix branch and a real
Linux run, not by the original sweep.

## Perf sweeps (branches `ds4/…`, `reviews/2026-08-09`) — no change made

- "zstd 19 is not matched for the libzim runs" — false positive. libzim
  hardcodes level 19 and exposes no knob; `ZSTD_CLEVEL=19` is what brings
  zimru *up* to it. The README's methodology section says so.
- "`make_shared` / move the item handle in the recreate loop" — declined. The
  harness mirrors upstream `zimrecreate` on purpose (that is what "baseline"
  means), and the later Pi sweep independently judged the cost negligible
  next to 2 MB-cluster zstd 19.

## Related, not from this sweep

`bench/fetch-baseline.sh` (new) pulls published release tarballs instead of
building libzim from source, and **verifies each against the `.md5` sidecar
openzim publishes next to it**. An unverified download is how a nominally
pinned baseline still ends up being whatever a proxy felt like serving.
The download goes to `.part` (resumable with `-C -`) and is renamed only after
it verifies, so a dropped connection can neither leave a half file under the
real name nor force a from-zero retry; a sidecar that is not a hex digest, a
mismatching download and a stale cached file are each refused and removed.
The sidecar is served by the same host as the tarball, so this detects
corruption and proxies, not a compromised origin.
Verified working: libzim 9.8.2 `d294ffbd…`, zim-tools 3.8.0 `b96a3ad4…`.
