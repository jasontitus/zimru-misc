#!/usr/bin/env bash
# Benchmark: zimru + xapianbuilder  vs  libzim 9.7.0 (in-process Xapian)
#
# Apples-to-apples ZIM recreate: same source archive, matched zstd level 19,
# all cores. Measures the full recreate (read + index + compress + write)
# both WITH and WITHOUT the fulltext/title index, so the indexer cost can be
# isolated by subtraction.
#
# Config via env (defaults match the build-baseline.sh layout):
#   PREFIX         libzim 9.7.0 install prefix      (default: $BUILD/prefix)
#   LIBZIM         path to the zimrecreate_libzim baseline harness
#   ZIMRU          path to zimru's zimrecreate binary
#   XAPIANBUILDER  path to the xapianbuilder helper (zimru spawns it)
#   PY             python with the libzim bindings (for verification)
#   NPROC          worker threads                   (default: nproc)
#   RUNS           timed runs per config, best kept (default: 2; use 1 for huge ZIMs)
#   OUT            output dir for recreated ZIMs     (default: /tmp/zbench)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:-$HERE/../build}
PREFIX=${PREFIX:-$BUILD/prefix}
LIBZIM=${LIBZIM:-$BUILD/zimrecreate_libzim}
ZIMRU=${ZIMRU:-$(command -v zimrecreate || echo /storage/zimru/target/release/zimrecreate)}
XAPIANBUILDER=${XAPIANBUILDER:-$(command -v xapianbuilder || echo /home/ot/.local/bin/xapianbuilder)}
PY=${PY:-python3}
NPROC=${NPROC:-$(nproc)}
OUT=${OUT:-/tmp/zbench}
export LD_LIBRARY_PATH=$PREFIX/lib/x86_64-linux-gnu:$PREFIX/lib:${LD_LIBRARY_PATH:-}
export XAPIANBUILDER
mkdir -p "$OUT"

timeit() {  # timeit <label> <outfile> -- cmd...
  local label=$1 outfile=$2; shift 3
  rm -f "$outfile"
  local best=99999 t start end rc
  for r in $(seq 1 ${RUNS:-2}); do
    start=$(date +%s.%N); "$@" >/dev/null 2>&1; rc=$?; end=$(date +%s.%N)
    t=$(awk "BEGIN{print $end-$start}")
    [ $rc -ne 0 ] && { echo "$label: FAILED rc=$rc"; return 1; }
    awk "BEGIN{exit !($t<$best)}" && best=$t
  done
  local sz=$(stat -c%s "$outfile" 2>/dev/null)
  printf "%-34s %8.1fs  %9.1f MB\n" "$label" "$best" "$(awk "BEGIN{print $sz/1048576}")"
}

idxcheck() { $PY - "$1" <<'PY'
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
PY
}

for SRC in "$@"; do
  name=$(basename "$SRC" .zim)
  echo "================================================================"
  printf "SOURCE: %s  (%.0f MB)\n" "$SRC" "$(awk "BEGIN{print $(stat -c%s "$SRC")/1048576}")"
  $PY -c "from libzim.reader import Archive;a=Archive('$SRC');print('   source: entries=%d FT=%s title=%s'%(a.all_entry_count,a.has_fulltext_index,a.has_title_index))"
  cat "$SRC" >/dev/null  # warm page cache equally for both tools
  echo "--- WITH fulltext+title index (matched zstd 19) ---"
  timeit "libzim9.7.0  +index" "$OUT/$name.lz.idx.zim" -- "$LIBZIM" "$SRC" "$OUT/$name.lz.idx.zim" $NPROC 2097152 1
  idxcheck "$OUT/$name.lz.idx.zim"
  timeit "zimru+xapianbuilder +index" "$OUT/$name.zr.idx.zim" -- env ZSTD_CLEVEL=19 "$ZIMRU" "$SRC" "$OUT/$name.zr.idx.zim" -J $NPROC
  idxcheck "$OUT/$name.zr.idx.zim"
  echo "--- NO index, build/compress only (matched zstd 19) ---"
  timeit "libzim9.7.0  no-index" "$OUT/$name.lz.nox.zim" -- "$LIBZIM" "$SRC" "$OUT/$name.lz.nox.zim" $NPROC 2097152 0
  timeit "zimru no-index" "$OUT/$name.zr.nox.zim" -- env ZSTD_CLEVEL=19 "$ZIMRU" "$SRC" "$OUT/$name.zr.nox.zim" -J $NPROC -j
  echo
done
