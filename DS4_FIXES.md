# Disposition of the DS4 sweep — zimru-misc

Three findings, all about the benchmark baseline's supply chain. All fixed.

| Finding | What was wrong | Fix |
|---|---|---|
| [medium] `bench/build-baseline.sh:46` | libzim was cloned from **unpinned git master** while the comment claimed "libzim 9.7.0". The baseline silently drifted to whatever upstream happened to be that day, which makes the apples-to-apples comparison mean something different from one run to the next — the one property a baseline exists to have. | Pinned: `git clone --branch "$LIBZIM_TAG"`, defaulting to 9.8.2 and overridable as `$1` or `$LIBZIM_TAG`. Comments now say pinned rather than naming a version the script did not fetch. |
| [low] `bench/build-baseline.sh:35` | The xz 5.4.6 release tarball was fetched over TLS and built unverified. | `sha256sum -c` against a pinned digest, captured from the published artefact. The comment is explicit that pinning makes a *later* substitution detectable and is not a substitute for verifying the upstream signature when first adopting a version. |
| [low] `bench/bench.sh:64` | `timeit` swallowed the tool's exit status, so a run that failed partway was still reported as a timing. | Superseded: the creation comparison now lives in zimru's `bench/creation-bench.sh`, which reports FAIL explicitly, and the read-side one in `bench/toolset-bench.sh`, which prints both tools' exit codes. Kept because a fast run and a crashed run are otherwise indistinguishable — upstream's `zimbench` exits 0 without doing the work. |

## Related, not from this sweep

`bench/fetch-baseline.sh` (new) pulls published release tarballs instead of
building libzim from source, and **verifies each against the `.md5` sidecar
openzim publishes next to it**. An unverified download is how a nominally
pinned baseline still ends up being whatever a proxy felt like serving.
Verified working: libzim 9.8.2 `d294ffbd…`, zim-tools 3.8.0 `b96a3ad4…`.
