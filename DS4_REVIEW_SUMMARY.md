# Executive Summary — zimru-misc

## 1. Verdict

Healthy. The reviewed surface is a small benchmark harness (3 files: two shell
scripts + one clean C++ file), not production or user-facing code. No genuinely
exploitable issue was found — no injection reachable from untrusted input, no
auth/SSRF/traversal, no committed credentials. The one finding that actually
matters is a **benchmark-integrity** bug, not a security bug.

**Severity counts: High 0 · Medium 1 · Low 2.**

## 2. Fix first (highest opportunity)

1. **[medium] `bench/build-baseline.sh:46` — unpinned libzim baseline silently
   invalidates the benchmark.** The script clones libzim from `git master`
   (`git clone -q --depth 1 https://github.com/openzim/libzim.git`) while the
   comment and intent claim "libzim 9.7.0". The "9.7.0 baseline" therefore
   drifts to whatever master is on run day, so every apples-to-apples comparison
   is quietly measuring against a moving target — silent result corruption, the
   highest-impact issue here because it undermines the whole reason the harness
   exists.
   **Fix:** pin the tag — `git clone -q --depth 1 --branch v9.7.0 https://github.com/openzim/libzim.git`.

2. **[low] `bench/bench.sh:64` — `$SRC` interpolated into a `python -c` source
   string (code-injection class).** A path containing a quote, newline, or shell
   metacharacter breaks or injects into the Python one-liner
   (`Archive('$SRC')` → `Archive('foo'));<code>`). This is the injection-class
   finding, so worth fixing on principle, but `$SRC` is an operator-supplied
   archive path (not untrusted external input) on a dev benchmark path — hence
   genuinely low, not high.
   **Fix:** pass the path as argv and read it in Python —
   `$PY -c "...sys.argv[1]..." "$SRC"`; never interpolate into source text.

3. **[low] `bench/build-baseline.sh:35` — xz 5.4.6 tarball fetched with no
   checksum verification.** `curl -fsSL` pulls the release and builds/installs
   it without a pinned SHA256, so a tampered upstream artifact is trusted
   blindly. Low because it depends on upstream/MITM compromise and only affects
   the benchmark toolchain, but a one-line fix.
   **Fix:** pin and verify before extract —
   `echo "<sha256>  $SRC/xz.tar.gz" | sha256sum -c -`.

## 3. Systemic patterns

- **Unpinned / unverified external dependencies (2 of 3 findings).** Both
  `build-baseline.sh` issues (#1 and #3) are the same class: fetching build
  inputs without pinning to an immutable, verified version. Fixing the class —
  pin every external fetch to a tag/commit *and* verify a checksum — closes both
  and hardens reproducibility of the whole baseline. This is the pattern to fix,
  not the two instances.

- **Shell hygiene note:** No `set -e`-without-`pipefail` pipeline-swallowing
  issue was flagged in this report, and no committed-credential finding appeared
  — both clean on this pass.

## 4. Lower priority / hygiene

- The `python -c` interpolation (#2) is really injection-hardening hygiene given
  the operator-controlled input; treat it as robustness cleanup rather than a
  security fix.
- `bench/zimrecreate_libzim.cpp` reviewed clean.

## 5. Caveats

- Findings are **model-generated** (DeepSeek sweep) and severities were
  **model-assigned**; not every line was source-verified. Confirm the exact
  lines before acting — especially the medium (#1): verify the clone command and
  the "9.7.0" comment actually conflict at `build-baseline.sh:46` before pinning.
- No committed-credential findings surfaced, so nothing to rotate here — but that
  is the sweep's conclusion, not an independent audit.
