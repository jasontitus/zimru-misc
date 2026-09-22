#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fetch a *released* libzim + zim-tools as the benchmark baseline, instead of
# building libzim from source at a pinned tag (build-baseline.sh).
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
# Output: $BUILD/libzim-<v>/{include,lib/<multiarch>}
#         (ARCH=linux-aarch64 etc. selects another published build)
#
# Known upstream problem, 2026-09-19: zim-tools_linux-aarch64-3.8.0.tar.gz does
# not match its own published .md5 (two independent full downloads, right
# size, intact gzip, both md5 3bdebffe…; sidecar says e219ad2a…). This script
# refuses it, which is the point; there is deliberately no override. The
# x86_64 artefacts and libzim_linux-aarch64-9.8.2 verify. On aarch64 use
# build-baseline.sh until openzim republishes.
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
# Scope: the sidecar comes from the same host as the tarball, so this catches
# truncation, corruption and a meddling proxy — not a compromised origin.
fetch() {
  local url="$1" dest="$2" want got
  want=$(curl -fsSL --retry 3 "$url.md5" | awk '{print $1}') || want=
  case $want in
    *[!0-9a-f]*|'') echo "could not fetch a usable $url.md5 — refusing to use an unverified baseline" >&2; exit 1;;
  esac
  # Download to .part and only rename once verified, so $dest is never a
  # half-written or unverified file. -C - resumes a .part left by a dropped
  # connection (these are 10-75 MB from a sometimes slow server); if what it
  # resumed was bad, the checksum fails, the .part is deleted, and the next
  # run starts clean.
  if [ ! -f "$dest" ]; then
    curl -fL --silent --show-error --retry 4 --retry-delay 3 -C - -o "$dest.part" "$url"
    got=$(md5sum "$dest.part" | awk '{print $1}')
    if [ "$want" != "$got" ]; then
      rm -f "$dest.part"
      echo "checksum mismatch for $(basename "$dest") (download removed)" >&2
      echo "  expected $want" >&2
      echo "  got      $got" >&2
      exit 1
    fi
    mv "$dest.part" "$dest"
  fi
  # A $dest from an earlier run is re-checked too: the sidecar may be for a
  # different version than the one cached under this name.
  got=$(md5sum "$dest" | awk '{print $1}')
  if [ "$want" != "$got" ]; then
    rm -f "$dest"
    echo "checksum mismatch for cached $(basename "$dest") (removed; re-run to download again)" >&2
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
# The release tarballs use the Debian multiarch libdir for their own $ARCH.
LIBDIR=$LZ/lib
for d in "$LZ"/lib/*-linux-gnu*; do [ -d "$d" ] && LIBDIR=$d; done

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
