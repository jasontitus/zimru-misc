#!/usr/bin/env bash
# Fetch a *released* libzim + zim-tools as the benchmark baseline, instead of
# building libzim from git master (build-baseline.sh).
#
# Why this exists alongside build-baseline.sh:
#   * It pins an exact published release, so a benchmark run is reproducible
#     and the reported "upstream" version is a real version number rather
#     than whatever master happened to be that day.
#   * It only needs download.openzim.org — no GitHub, no meson/ninja, no
#     libzim build. Useful on hosts where the toolchain or the network is
#     restricted.
#   * zim-tools ships the reference `zimrecreate` binary, which is the tool
#     the creation benchmark actually compares against; the libzim package
#     supplies headers + libzim.so for the `zimrecreate_libzim` harness (and
#     for anything else that wants to link libzim directly).
#
# Usage:  BUILD=/path/to/scratch ./fetch-baseline.sh [libzim_version] [zimtools_version]
# Output: $BUILD/libzim-<v>/{include,lib/x86_64-linux-gnu}
#         $BUILD/zim-tools-<v>/                 (zimrecreate, zimcheck, …)
#         $BUILD/zimrecreate_libzim             (harness, if it compiles)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:?set BUILD to a writable scratch dir}
LIBZIM_V=${1:-9.8.2}
ZIMTOOLS_V=${2:-3.8.0}
ARCH=${ARCH:-linux-x86_64}
mkdir -p "$BUILD"

# fetch <url> <dest> — download and verify against the .md5 sidecar openzim
# publishes next to every release artefact. An unverified download is how a
# "pinned" baseline still ends up being whatever a proxy felt like serving.
fetch() {
  local url="$1" dest="$2" want got
  [ -f "$dest" ] || curl -fL --silent --show-error --retry 4 --retry-delay 3 -o "$dest" "$url"
  want=$(curl -fsSL --retry 3 "$url.md5" | awk '{print $1}') || {
    echo "could not fetch $url.md5 — refusing to use an unverified baseline" >&2
    exit 1
  }
  got=$(md5sum "$dest" | awk '{print $1}')
  if [ "$want" != "$got" ]; then
    echo "checksum mismatch for $dest" >&2
    echo "  expected $want" >&2
    echo "  got      $got" >&2
    rm -f "$dest"
    exit 1
  fi
  echo "   verified $(basename "$dest")  md5 $got"
}

echo "== libzim $LIBZIM_V ($ARCH) =="
fetch "https://download.openzim.org/release/libzim/libzim_${ARCH}-${LIBZIM_V}.tar.gz" \
      "$BUILD/libzim.tar.gz"
rm -rf "$BUILD/libzim-$LIBZIM_V"; mkdir -p "$BUILD/libzim-$LIBZIM_V"
tar -xzf "$BUILD/libzim.tar.gz" -C "$BUILD/libzim-$LIBZIM_V" --strip-components=1

echo "== zim-tools $ZIMTOOLS_V ($ARCH) =="
fetch "https://download.openzim.org/release/zim-tools/zim-tools_${ARCH}-${ZIMTOOLS_V}.tar.gz" \
      "$BUILD/zim-tools.tar.gz"
rm -rf "$BUILD/zim-tools-$ZIMTOOLS_V"; mkdir -p "$BUILD/zim-tools-$ZIMTOOLS_V"
tar -xzf "$BUILD/zim-tools.tar.gz" -C "$BUILD/zim-tools-$ZIMTOOLS_V" --strip-components=1

LZ="$BUILD/libzim-$LIBZIM_V"
LIBDIR="$LZ/lib/x86_64-linux-gnu"
[ -d "$LIBDIR" ] || LIBDIR="$LZ/lib"

echo "== zimrecreate_libzim harness =="
if g++ -O2 -std=c++17 "$HERE/zimrecreate_libzim.cpp" \
       -I"$LZ/include" -L"$LIBDIR" -Wl,-rpath,"$LIBDIR" -lzim \
       -o "$BUILD/zimrecreate_libzim" 2>"$BUILD/harness-build.log"; then
  echo "   -> $BUILD/zimrecreate_libzim"
else
  echo "   harness did not compile against libzim $LIBZIM_V; see $BUILD/harness-build.log" >&2
  echo "   (the zim-tools zimrecreate binary below works as the baseline either way)" >&2
fi

echo
echo "Baseline ready:"
echo "  upstream zimrecreate : $BUILD/zim-tools-$ZIMTOOLS_V/zimrecreate"
echo "  libzim headers/lib   : $LZ/include, $LIBDIR"
echo
echo "Run the recreate benchmark with:"
echo "  UPSTREAM_DIR=$BUILD/zim-tools-$ZIMTOOLS_V \\"
echo "  XAPIANBUILDER=/path/to/xapianbuilder \\"
echo "  /path/to/zimru/bench/creation-bench.sh SOURCE.zim"
