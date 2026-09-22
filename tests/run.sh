#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests for the bench/ harness. No network, no real benchmark run.
#
#   ./tests/run.sh                 lint + script behaviour
#   TEST_ZIM=some.zim ./tests/run.sh   also build the C++ tools against the
#                                  installed libzim and run them on that file
#   ZIM_FLAGS="-I… -L… -lzim -lcrypto"  compiler/linker flags for that build,
#                                  when pkg-config cannot supply them
#
# The behaviour tests drive bench.sh with stub tools and a fake `libzim`
# Python module, so they exercise the real script text rather than a copy.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

# bench.sh needs GNU stat/date/nproc. On macOS, borrow coreutils' g-prefixed
# ones through a shim dir; without them the bench.sh tests are skipped.
SHIM=$T/shim; mkdir -p "$SHIM"
GNU=1
if ! stat -c%s "$0" >/dev/null 2>&1; then
  for t in stat date nproc sha256sum md5sum; do
    if command -v "g$t" >/dev/null; then ln -s "$(command -v "g$t")" "$SHIM/$t"; else GNU=0; fi
  done
fi

echo "== lint =="
for f in "$ROOT"/bench/*.sh "$ROOT"/tests/*.sh; do
  check "parses: ${f#"$ROOT"/}" /bin/bash -n "$f"
  check "starts strict (set -euo pipefail): ${f#"$ROOT"/}" grep -q '^set -euo pipefail$' "$f"
  # bash -n cannot see these: on bash 3.2 they parse, then misbehave at runtime.
  # (This file names them in the pattern itself; running it under macOS's
  # /bin/bash 3.2 is its own proof.)
  case $f in */tests/run.sh) continue;; esac
  if grep -nE '\b(mapfile|readarray)\b|declare -A|\$\{[A-Za-z_]+(,,|\^\^)\}' "$f"; then bad "no bash-4-only constructs: ${f#"$ROOT"/}"
  else ok "no bash-4-only constructs: ${f#"$ROOT"/}"; fi
done
if command -v shellcheck >/dev/null; then
  check "shellcheck" shellcheck -S warning "$ROOT"/bench/*.sh "$ROOT"/tests/*.sh
else
  echo "skip  shellcheck (not installed)"
fi
# Two cheap greps for a shell variable reaching Python source: inside a
# `-c "…"` string, or through an unquoted heredoc. Neither is exhaustive — the
# PWNED test below is the one that actually executes the attack.
if grep -nE -- "-c +\"[^\"]*\\$" "$ROOT"/bench/*.sh; then
  bad "no shell variable interpolated into python -c source"
else
  ok "no shell variable interpolated into python -c source"
fi

if grep -nE -- "[$]PY .*<<-?[A-Za-z_]" "$ROOT"/bench/*.sh; then bad "python heredocs are quoted (<<'PY')"
else ok "python heredocs are quoted (<<'PY')"; fi

echo "== build-baseline.sh: a reused checkout must be the pinned tag =="
# Pull the real function out of the script rather than re-typing it here.
sed -n '/^clone_pinned() {$/,/^}$/p' "$ROOT/bench/build-baseline.sh" > "$T/clone_pinned.sh"
check "clone_pinned extracted" test -s "$T/clone_pinned.sh"
UP=$T/upstream
git init -q "$UP"
git -C "$UP" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
git -C "$UP" tag 1.0.0
git -C "$UP" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
git -C "$UP" tag 2.0.0
git -C "$UP" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m untagged-master
run_cp() { ( set -euo pipefail; . "$T/clone_pinned.sh"; clone_pinned "$@" ) >"$T/cp.out" 2>&1; }
check "fresh clone of a tag succeeds"            run_cp "file://$UP" 1.0.0 "$T/co"
check "re-run against the same tag succeeds"     run_cp "file://$UP" 1.0.0 "$T/co"
if run_cp "file://$UP" 2.0.0 "$T/co"; then bad "existing checkout at another tag is refused"
else ok "existing checkout at another tag is refused"; fi
git clone -q "file://$UP" "$T/master"
if run_cp "file://$UP" 2.0.0 "$T/master"; then bad "leftover master checkout is refused"
else ok "leftover master checkout is refused"; fi
# Shallow, as the real script clones; two tags on one commit must not confuse it.
git -C "$UP" tag also-2.0.0 2.0.0
check "shallow clone of a commit carrying two tags succeeds" run_cp "file://$UP" 2.0.0 "$T/two"
GOOD=$(git -C "$UP" rev-parse '2.0.0^{commit}')
check "matching recorded commit is accepted" run_cp "file://$UP" 2.0.0 "$T/two" "$GOOD"
if run_cp "file://$UP" 2.0.0 "$T/two" 0000000000000000000000000000000000000000; then bad "moved tag (commit mismatch) is refused"
else ok "moved tag (commit mismatch) is refused"; fi
# Untracked files must NOT refuse: a real meson build of libzim leaves
# subprojects/googletest-*/ in the tree, and the re-run has to work.
mkdir -p "$T/two/subprojects/packagecache"; echo x > "$T/two/subprojects/packagecache/gtest.zip"
check "build leftovers (untracked files) do not block a re-run" run_cp "file://$UP" 2.0.0 "$T/two" "$GOOD"
echo tampered > "$T/two/f"; git -C "$T/two" add f
if run_cp "file://$UP" 2.0.0 "$T/two" "$GOOD"; then bad "locally modified checkout is refused"
else ok "locally modified checkout is refused"; fi
# A plain directory inside another repository that happens to be AT the tag:
# git -C would answer for the enclosing repo and wave it through.
git clone -q --branch 2.0.0 "file://$UP" "$T/outer" 2>/dev/null; mkdir "$T/outer/notrepo"
if run_cp "file://$UP" 2.0.0 "$T/outer/notrepo"; then bad "non-repo dir inside an enclosing repo is refused"
else ok "non-repo dir inside an enclosing repo is refused"; fi

echo "== build-baseline.sh: checksum verification =="
sed -n '/^verify_sha256() {$/,/^}$/p' "$ROOT/bench/build-baseline.sh" > "$T/verify.sh"
check "verify_sha256 extracted" test -s "$T/verify.sh"
if ! PATH="$SHIM:$PATH" command -v sha256sum >/dev/null; then
  echo "skip  verify_sha256 behaviour (no sha256sum)"
else
  run_v() { ( set -euo pipefail; PATH="$SHIM:$PATH"; . "$T/verify.sh"; verify_sha256 "$@" ) >"$T/v.out" 2>&1; }
  printf 'payload' > "$T/dl with space.tgz"
  SUM=$(PATH="$SHIM:$PATH" sha256sum "$T/dl with space.tgz" | awk '{print $1}')
  check "matching digest is accepted" run_v "$T/dl with space.tgz" "$SUM"
  check "…and the file is kept" test -f "$T/dl with space.tgz"
  if run_v "$T/dl with space.tgz" "${SUM%?}0x"; then bad "wrong digest is refused"; else ok "wrong digest is refused"; fi
  check "…and the bad file is deleted" test ! -e "$T/dl with space.tgz"
  # The class: the script must not skip verification because something is already there.
  if grep -nE '^\s*(if )?\[ ! -d .*xz' "$ROOT/bench/build-baseline.sh"; then bad "xz verification is not guarded by an already-extracted check"
  else ok "xz verification is not guarded by an already-extracted check"; fi
fi

check "the pinned default tags carry recorded commits" sh -c "grep -q '^ZSTD_COMMIT=[0-9a-f]\{40\}$' '$ROOT/bench/build-baseline.sh' && grep -q '9.8.2) LIBZIM_COMMIT=[0-9a-f]\{40\} ;;' '$ROOT/bench/build-baseline.sh'"

echo "== fetch-baseline.sh: fetch() against a local file:// 'server' =="
sed -n '/^fetch() {$/,/^}$/p' "$ROOT/bench/fetch-baseline.sh" > "$T/fetch.sh"
check "fetch extracted" test -s "$T/fetch.sh"
if ! PATH="$SHIM:$PATH" command -v md5sum >/dev/null || ! command -v curl >/dev/null; then
  echo "skip  fetch behaviour (needs md5sum + curl)"
else
  W=$T/www; D=$T/dl; mkdir -p "$W" "$D"
  run_f() { ( set -euo pipefail; PATH="$SHIM:$PATH"; . "$T/fetch.sh"; fetch "$@" ) >"$T/f.out" 2>&1; }
  printf 'release-bytes' > "$W/a.tgz"
  (cd "$W" && PATH="$SHIM:$PATH" md5sum a.tgz > a.tgz.md5)
  check "download matching its sidecar is accepted" run_f "file://$W/a.tgz" "$D/a.tgz"
  check "…leaving no .part behind" test ! -e "$D/a.tgz.part"
  check "cached verified file is accepted again" run_f "file://$W/a.tgz" "$D/a.tgz"
  printf 'proxy-served-something-else' > "$W/b.tgz"; cp "$W/a.tgz.md5" "$W/b.tgz.md5"
  if run_f "file://$W/b.tgz" "$D/b.tgz"; then bad "download not matching its sidecar is refused"; else ok "download not matching its sidecar is refused"; fi
  check "…and nothing is left to be picked up later" sh -c "! ls '$D'/b.tgz* >/dev/null 2>&1"
  printf 'x' > "$W/c.tgz"
  if run_f "file://$W/c.tgz" "$D/c.tgz"; then bad "missing sidecar is refused"; else ok "missing sidecar is refused"; fi
  check "…before anything is downloaded" sh -c "! ls '$D'/c.tgz* >/dev/null 2>&1"
  printf '<html>404</html>\n' > "$W/c.tgz.md5"
  if run_f "file://$W/c.tgz" "$D/c.tgz"; then bad "sidecar that is not a digest is refused"; else ok "sidecar that is not a digest is refused"; fi
  printf 'stale-cache' > "$D/a.tgz"
  if run_f "file://$W/a.tgz" "$D/a.tgz"; then bad "cached file that no longer matches is refused"; else ok "cached file that no longer matches is refused"; fi
  check "…and removed so the next run re-downloads" test ! -e "$D/a.tgz"
fi

echo "== bench.sh =="
if [ "$GNU" -ne 1 ]; then
  echo "skip  bench.sh behaviour (needs GNU stat/date/nproc)"
else
  B=$T/bench; mkdir -p "$B/py/libzim" "$B/out" "$B/cwd"
  : > "$B/py/libzim/__init__.py"
  cat > "$B/py/libzim/reader.py" <<'PY'
import os
class Archive:
    all_entry_count = 0
    def __init__(self, path):
        open(path, "rb").close()   # a path that is not a real file is an error
        # FAKE_NOINDEX=<substring>: archives whose name contains it have no
        # indexes — what zimru writes when xapianbuilder is broken.
        miss = os.environ.get("FAKE_NOINDEX")
        self.has_fulltext_index = self.has_title_index = not (miss and miss in path)
PY
  printf '#!/bin/sh\nprintf data > "$2"\n'   > "$B/good";    chmod +x "$B/good"
  printf '#!/bin/sh\nexit 7\n'                > "$B/crash";   chmod +x "$B/crash"
  printf '#!/bin/sh\nexit 0\n'                > "$B/noop";    chmod +x "$B/noop"
  bench() {  # bench <libzim-stub> <zimru-stub> <xapianbuilder> <source>
    # shellcheck disable=SC2086  # EXTRA is a list of VAR=value words
    ( cd "$B/cwd" && env PATH="$SHIM:$PATH" PYTHONPATH="$B/py" PY=python3 RUNS=1 OUT="$B/out" \
        LIBZIM="$1" ZIMRU="$2" XAPIANBUILDER="$3" LIBZIM_VERSION=0.0.0 ${EXTRA:-} \
        /bin/bash "$ROOT/bench/bench.sh" "$4" ) >"$B/log" 2>&1
  }
  printf zim > "$B/plain.zim"
  check "happy path exits 0" bench "$B/good" "$B/good" "$B/good" "$B/plain.zim"
  check "rows carry the configured libzim version, not a hardcoded one" grep -q 'libzim 0.0.0  +index' "$B/log"

  # A source path that is valid shell and valid Python-string-breaking text.
  EVIL="$B/a'+__import__('os').system('touch PWNED')+'.zim"
  printf zim > "$EVIL"
  check "quote-bearing source path still benchmarks" bench "$B/good" "$B/good" "$B/good" "$EVIL"
  check "…and its text is never executed as Python" test ! -e "$B/cwd/PWNED"

  if bench "$B/crash" "$B/good" "$B/good" "$B/plain.zim"; then bad "crashed tool makes bench.sh exit nonzero"
  else ok "crashed tool makes bench.sh exit nonzero"; fi
  check "crash is reported with its exit code" grep -q 'FAILED rc=7' "$B/log"
  check "other rows still ran after the crash" grep -q '^zimru no-index .* MB$' "$B/log"

  if bench "$B/good" "$B/noop" "$B/good" "$B/plain.zim"; then bad "exit 0 with no output is a failure, not a timing"
  else ok "exit 0 with no output is a failure, not a timing"; fi
  check "no-output failure is named" grep -q 'FAILED (exit 0 but no output' "$B/log"

  # RUNS=2, tool writes on its first call only: run 1's file must not vouch for run 2.
  cat > "$B/once" <<'SH'
#!/bin/sh
m="$2.ran"; if [ -e "$m" ]; then exit 0; fi; : > "$m"; printf data > "$2"
SH
  chmod +x "$B/once"
  if EXTRA="RUNS=2" bench "$B/good" "$B/once" "$B/good" "$B/plain.zim"; then bad "a no-output REPEAT run is a failure too (RUNS=2)"
  else ok "a no-output REPEAT run is a failure too (RUNS=2)"; fi
  check "…named as such, for the zimru row" grep -q '^zimru+xapianbuilder +index: FAILED (exit 0 but no output' "$B/log"
  if EXTRA="RUNS=2" bench "$B/good" "$B/good" "$B/good" "$B/plain.zim"; then ok "RUNS=2 with honest tools exits 0"; else bad "RUNS=2 with honest tools exits 0"; fi

  # zimru ran "successfully" but its +index output has no index (broken helper).
  if EXTRA="FAKE_NOINDEX=.zr.idx" bench "$B/good" "$B/good" "$B/good" "$B/plain.zim"; then bad "+index row without an index makes bench.sh exit nonzero"
  else ok "+index row without an index makes bench.sh exit nonzero"; fi
  check "…and says which row" grep -q '^zimru+xapianbuilder +index: FAILED (index missing' "$B/log"
  check "…while the libzim +index row passed" sh -c "! grep -q '^libzim.*+index: FAILED' '$B/log'"

  # Version label read from a real libzim.pc when LIBZIM_VERSION is not given.
  mkdir -p "$B/prefix/lib/pkgconfig"; printf 'Name: libzim\nVersion: 7.7.7\n' > "$B/prefix/lib/pkgconfig/libzim.pc"
  bench_pc() { ( cd "$B/cwd" && env PATH="$SHIM:$PATH" PYTHONPATH="$B/py" PY=python3 RUNS=1 OUT="$B/out" PREFIX="$B/prefix" \
      LIBZIM="$B/good" ZIMRU="$B/good" XAPIANBUILDER="$B/good" /bin/bash "$ROOT/bench/bench.sh" "$B/plain.zim" ) >"$B/log" 2>&1; }
  check "bench.sh runs with a PREFIX" bench_pc
  check "row label version comes from the installed libzim.pc" grep -q '^libzim 7.7.7  +index' "$B/log"

  printf zim > "$B/second.zim"
  bench2() { ( cd "$B/cwd" && env PATH="$SHIM:$PATH" PYTHONPATH="$B/py" PY=python3 RUNS=1 OUT="$B/out" \
      LIBZIM="$B/good" ZIMRU="$B/good" XAPIANBUILDER="$B/good" /bin/bash "$ROOT/bench/bench.sh" "$@" ) >"$B/log" 2>&1; }
  if bench2 "$B/missing.zim" "$B/second.zim"; then bad "unreadable source makes bench.sh exit nonzero"
  else ok "unreadable source makes bench.sh exit nonzero"; fi
  check "…but the next source is still benchmarked" grep -q '^zimru no-index .* MB$' "$B/log"

  if bench "$B/good" "$B/good" "$B/does-not-exist" "$B/plain.zim"; then bad "missing xapianbuilder refuses to start"
  else ok "missing xapianbuilder refuses to start"; fi
  check "no host-specific fallback paths" sh -c "! grep -nE '/home/|/storage/[a-z]+/target' '$ROOT/bench/bench.sh'"
fi

echo "== C++ tools (real libzim) =="
if [ -z "${TEST_ZIM:-}" ]; then
  echo "skip  set TEST_ZIM=file.zim to build and run them"
elif [ -z "${ZIM_FLAGS:=$(pkg-config --cflags --libs libzim libcrypto 2>"$T/pc.err" || true)}" ]; then
  # --exists is not enough: it passes while a transitive .pc (ICU on
  # Homebrew) is missing, and the compile then fails on an empty flag list.
  echo "skip  pkg-config cannot resolve libzim + libcrypto ($(head -1 "$T/pc.err")); set ZIM_FLAGS"
else
  C=$T/cpp; mkdir -p "$C"
  # shellcheck disable=SC2086  # a flag list; splitting is the point
  check "zimrecreate_libzim compiles" g++ -O2 -std=c++17 "$ROOT/bench/zimrecreate_libzim.cpp" -o "$C/recreate" $ZIM_FLAGS
  # shellcheck disable=SC2086
  check "zim-manifest compiles" g++ -O2 -std=c++17 "$ROOT/bench/zim-manifest.cpp" -o "$C/manifest" $ZIM_FLAGS
  check "recreate runs" "$C/recreate" "$TEST_ZIM" "$C/out.zim" 2 2097152 1
  "$C/manifest" "$TEST_ZIM"  | LC_ALL=C sort > "$C/src.manifest"
  "$C/manifest" "$C/out.zim" | LC_ALL=C sort > "$C/out.manifest"
  check "source manifest is non-empty" test -s "$C/src.manifest"
  # The recreate rebuilds indexes, listings and Counter; all user content
  # (everything else) must come through byte-identical.
  user() { grep -vE '^(fulltext/xapian|title/xapian|listing/|Counter	)' "$1" || true; }
  user "$C/src.manifest" > "$C/src.user"; user "$C/out.manifest" > "$C/out.user"
  check "recreated content is byte-identical to the source" diff "$C/src.user" "$C/out.user"
  if "$C/manifest" "$T/nope.zim" >/dev/null 2>&1; then bad "zim-manifest fails on a missing archive"
  else ok "zim-manifest fails on a missing archive"; fi
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
