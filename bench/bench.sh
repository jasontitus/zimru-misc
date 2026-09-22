#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Benchmark: zimru + xapianbuilder  vs  libzim (in-process Xapian)
#
# Apples-to-apples ZIM recreate: same source archive, matched zstd level 19,
# all cores. Measures the full recreate (read + index + compress + write)
# both WITH and WITHOUT the fulltext/title index, so the indexer cost can be
# isolated by subtraction.
#
# Linux only (nproc, GNU stat/date).
#
# Config via env (defaults match the build-baseline.sh layout):
#   PREFIX         libzim install prefix            (default: $BUILD/prefix)
#   LIBZIM         path to the zimrecreate_libzim baseline harness
#   LIBZIM_VERSION version shown in the row labels  (default: read from libzim.pc)
#   ZIMRU          path to zimru's zimrecreate binary     (default: from $PATH)
#   XAPIANBUILDER  path to the xapianbuilder helper (zimru spawns it; default: from $PATH)
#   PY             python with the libzim bindings (for verification)
#   NPROC          worker threads                   (default: nproc)
#   RUNS           timed runs per config, best kept (default: 2; use 1 for huge ZIMs)
#   OUT            output dir for recreated ZIMs     (default: /tmp/zbench)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:-$HERE/../build}
PREFIX=${PREFIX:-$BUILD/prefix}
LIBZIM=${LIBZIM:-$BUILD/zimrecreate_libzim}
ZIMRU=${ZIMRU:-$(command -v zimrecreate || true)}
XAPIANBUILDER=${XAPIANBUILDER:-$(command -v xapianbuilder || true)}
PY=${PY:-python3}
NPROC=${NPROC:-$(nproc)}
OUT=${OUT:-/tmp/zbench}

[ $# -ge 1 ] || { echo "usage: $0 SOURCE.zim [SOURCE.zim ...]" >&2; exit 2; }

# GNU date/stat are load-bearing: BSD `date +%N` prints a literal "N" and BSD
# `stat -c` fails, which would turn every timing and size into garbage rather
# than into an error.
case $(date +%N 2>/dev/null) in ''|*[!0-9]*) echo "needs GNU date (date +%N); this harness is Linux-only" >&2; exit 1;; esac
stat -c%s "$0" >/dev/null 2>&1 || { echo "needs GNU stat (stat -c); this harness is Linux-only" >&2; exit 1; }

# No host-specific fallbacks: a wrong binary is worse than a clear error, and
# without xapianbuilder zimru silently skips the indexes.
[ -x "$LIBZIM" ] || { echo "baseline harness not found: $LIBZIM (run build-baseline.sh, or set LIBZIM)" >&2; exit 1; }
[ -n "$ZIMRU" ] && [ -x "$ZIMRU" ] || { echo "zimru zimrecreate not found; set ZIMRU" >&2; exit 1; }
[ -n "$XAPIANBUILDER" ] && [ -x "$XAPIANBUILDER" ] || { echo "xapianbuilder not found; set XAPIANBUILDER" >&2; exit 1; }

# Label rows with the libzim actually installed, not a version baked into
# this script: the baseline is pinned by build-baseline.sh and can be changed.
if [ -z "${LIBZIM_VERSION:-}" ]; then
  LIBZIM_VERSION=$(cat "$PREFIX"/lib/pkgconfig/libzim.pc "$PREFIX"/lib*/*/pkgconfig/libzim.pc "$PREFIX"/lib64/pkgconfig/libzim.pc 2>/dev/null \
    | awk -F': *' 'tolower($1)=="version"{print $2; exit}' || true)
fi
LZ_LABEL="libzim${LIBZIM_VERSION:+ $LIBZIM_VERSION}"

# build-baseline.sh installs to $PREFIX/lib; the multiarch dir covers prefixes
# built by older revisions of it.
MULTIARCH=$(uname -m)-linux-gnu
export LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/lib/$MULTIARCH:${LD_LIBRARY_PATH:-}
export XAPIANBUILDER
mkdir -p "$OUT"
FAILED=0

timeit() {  # timeit <label> <outfile> -- cmd...
  local label=$1 outfile=$2; shift 3
  local best=99999 t start end rc sz=
  for _ in $(seq 1 "${RUNS:-2}"); do
    # Removed and re-checked on EVERY run: a file left by run 1 would otherwise
    # vouch for a run 2 that exited 0 without writing anything, and that
    # no-op's time would win "best".
    rm -f "$outfile"
    rc=0
    start=$(date +%s.%N); "$@" >/dev/null 2>&1 || rc=$?; end=$(date +%s.%N)
    if [ "$rc" -ne 0 ]; then echo "$label: FAILED rc=$rc"; return 1; fi
    sz=$(stat -c%s "$outfile" 2>/dev/null || true)
    case $sz in ''|0) echo "$label: FAILED (exit 0 but no output at $outfile)"; return 1;; esac
    t=$(awk "BEGIN{print $end-$start}")
    if awk "BEGIN{exit !($t<$best)}"; then best=$t; fi
  done
  [ -n "$sz" ] || { echo "$label: FAILED (RUNS=${RUNS:-2} ran nothing)"; return 1; }
  printf "%-34s %8.1fs  %9.1f MB\n" "$label" "$best" "$(awk "BEGIN{print $sz/1048576}")"
}

# bench <label> <outfile> <expect-index:0|1> -- cmd...
# expect-index=1 means the output MUST contain a fulltext and a title index;
# an index-less archive in a "+index" row is a failed row, not a fast one.
# A failed row is reported and remembered; the remaining rows still run, and
# the script exits nonzero at the end.
bench() {
  local label=$1 outfile=$2 verify=$3; shift 3
  if timeit "$label" "$outfile" "$@"; then
    if [ "$verify" = 1 ]; then
      idxcheck "$outfile" "$SRC_HAS_FT" || { echo "$label: FAILED (index missing from output)"; FAILED=1; }
    fi
  else
    FAILED=1
  fi
}

# idxcheck <zim> <source-had-fulltext:True|False> — report the index blobs and
# fail if an index the row was supposed to build is absent. The title index is
# always required; fulltext only when the source had one (an archive with no
# indexable text legitimately gets none from either tool).
idxcheck() { $PY - "$1" "$2" <<'PY'
import sys
from libzim.reader import Archive
a=Archive(sys.argv[1]); fs=ts=0
for i in range(a.all_entry_count):
    try: e=a._get_entry_by_id(i)
    except Exception: continue
    if e.path=="fulltext/xapian": fs=e.get_item().size
    elif e.path=="title/xapian": ts=e.get_item().size
print(f"   -> entries={a.all_entry_count} FT={a.has_fulltext_index} title={a.has_title_index}"
      f"  ft_blob={fs/1048576:.2f}MB title_blob={ts/1048576:.2f}MB")
want_ft = sys.argv[2] == "True"
sys.exit(0 if a.has_title_index and (a.has_fulltext_index or not want_ft) else 1)
PY
}

for SRC in "$@"; do
  name=$(basename "$SRC" .zim)
  echo "================================================================"
  # A bad source fails its own section, like a bad row: later sources still run.
  if ! srcsz=$(stat -c%s "$SRC" 2>/dev/null); then
    echo "SOURCE: $SRC: FAILED (not readable)"; FAILED=1; continue
  fi
  printf "SOURCE: %s  (%.0f MB)\n" "$SRC" "$(awk "BEGIN{print $srcsz/1048576}")"
  # The path goes in as argv, never into the Python source text.
  if ! SRC_HAS_FT=$($PY -c "import sys;from libzim.reader import Archive;a=Archive(sys.argv[1]);print('   source: entries=%d FT=%s title=%s'%(a.all_entry_count,a.has_fulltext_index,a.has_title_index),file=sys.stderr);print(a.has_fulltext_index)" "$SRC"); then
    echo "SOURCE: $SRC: FAILED (libzim could not open it via $PY)"; FAILED=1; continue
  fi
  cat "$SRC" >/dev/null  # warm page cache equally for both tools
  echo "--- WITH fulltext+title index (matched zstd 19) ---"
  bench "$LZ_LABEL  +index" "$OUT/$name.lz.idx.zim" 1 -- "$LIBZIM" "$SRC" "$OUT/$name.lz.idx.zim" "$NPROC" 2097152 1
  bench "zimru+xapianbuilder +index" "$OUT/$name.zr.idx.zim" 1 -- env ZSTD_CLEVEL=19 "$ZIMRU" "$SRC" "$OUT/$name.zr.idx.zim" -J "$NPROC"
  echo "--- NO index, build/compress only (matched zstd 19) ---"
  bench "$LZ_LABEL  no-index" "$OUT/$name.lz.nox.zim" 0 -- "$LIBZIM" "$SRC" "$OUT/$name.lz.nox.zim" "$NPROC" 2097152 0
  bench "zimru no-index" "$OUT/$name.zr.nox.zim" 0 -- env ZSTD_CLEVEL=19 "$ZIMRU" "$SRC" "$OUT/$name.zr.nox.zim" -J "$NPROC" -j
  echo
done

if [ "$FAILED" -ne 0 ]; then echo "one or more runs FAILED — see above" >&2; exit 1; fi
