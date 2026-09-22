#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the "old fashioned libzim" benchmark baseline from source:
#   zstd 1.5.6 + xz/liblzma 5.4.6 + libzim (pinned tag) + the
#   zimrecreate_libzim harness, all into a local --prefix. No root needed.
#
# Every dependency is pinned. An unpinned baseline is not a baseline: it
# drifts to whatever upstream master happens to be that day, and the
# "apples-to-apples" comparison silently comes to mean something different
# from one run to the next.
#
# If you only need the reference binaries rather than a from-source build,
# fetch-baseline.sh pulls published release tarballs (and verifies them
# against the .md5 sidecars openzim publishes), which is faster and needs no
# meson/ninja.
#
# System prerequisites already expected on the host (install via your distro):
#   g++ (C++17), git, curl, pkg-config, libxapian-dev (>=1.4.12), libicu-dev,
#   and meson + ninja (pip install --user meson ninja, or distro packages).
#
# Everything else (zstd/lzma/libzim headers) is built here, because the
# stock distro packages ship only runtime .so's without dev headers.
#
# Usage:   BUILD=/storage/you/zimru-misc-build ./build-baseline.sh [libzim_tag]
#          One tag per BUILD dir: asking for a different tag on a reused BUILD
#          is refused rather than silently building the old checkout.
# Output:  $BUILD/prefix/...           (libzim + deps)
#          $BUILD/zimrecreate_libzim   (the baseline harness binary)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:?set BUILD to a writable dir on a data volume, e.g. /storage/you/zimru-misc-build}
PREFIX=$BUILD/prefix
SRC=$BUILD/src
mkdir -p "$SRC" "$PREFIX"
# Everything is installed with libdir=lib, so there is one path to find it on
# regardless of the distro's multiarch/lib64 convention.
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
JOBS=$(nproc)
LIBZIM_TAG=${1:-${LIBZIM_TAG:-9.8.2}}
# Commits behind the tags, so a moved tag is caught as well as a moved branch.
# Only the tags listed here are commit-checked; any other tag is pinned by
# name alone, and the script says so.
ZSTD_COMMIT=794ea1b0afca0f020f4e57b6732332231fb23c70
case $LIBZIM_TAG in
  9.8.2) LIBZIM_COMMIT=26ec526f74e8342a40da5ab14e364546988e0e1a ;;
  9.7.0) LIBZIM_COMMIT=92bf64eb9c79fa44d9baeeb80786d2ae3775fce7 ;;
  *)     LIBZIM_COMMIT=; echo "note: no recorded commit for libzim $LIBZIM_TAG — pinned by tag name only" >&2 ;;
esac
# Captured from the published artefact. Pinning is what makes a later
# substitution detectable; it is not a substitute for verifying the
# upstream signature the first time you adopt a version.
XZ_SHA256=aeba3e03bf8140ddedf62a0a367158340520f6b384f75ca6045ccc6c0d43fd5c

# clone_pinned <url> <tag> <dir> [commit] — clone a tag, or prove an existing
# checkout IS that tag. $SRC is reused between runs, so without this check a
# leftover clone (an old master checkout, or a different tag from an earlier
# run) would be built and reported as the pinned version: the pin would be a
# no-op. Compared by commit, not by `git describe`, because a commit can carry
# several tags. Where a commit is given it must match too: upstream can move a
# tag, it cannot move a SHA.
clone_pinned() {
  local url=$1 tag=$2 dir=$3 want_commit=${4:-} head tagged top
  [ -d "$dir" ] || git clone -q --depth 1 --branch "$tag" "$url" "$dir"
  # git -C on a directory that is not itself a repository silently answers
  # for whatever repository encloses it (this one, if BUILD is inside it).
  top=$(cd "$dir" && git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$(cd "$dir" && pwd -P)" ]; then
    echo "$dir exists but is not a git checkout of its own; remove it and re-run." >&2
    exit 1
  fi
  head=$(git -C "$dir" rev-parse --verify -q HEAD || true)
  tagged=$(git -C "$dir" rev-parse --verify -q "refs/tags/$tag^{commit}" || true)
  if [ -z "$head" ] || [ "$head" != "$tagged" ]; then
    echo "$dir is not at the pinned tag '$tag' (HEAD ${head:-unknown}, tag ${tagged:-not present})." >&2
    echo "Remove it (rm -rf \"$dir\") and re-run to fetch the pinned version." >&2
    exit 1
  fi
  if [ -n "$want_commit" ] && [ "$head" != "$want_commit" ]; then
    echo "$url tag '$tag' is $head, expected $want_commit — the tag has moved; refusing to build." >&2
    exit 1
  fi
  # Tracked files only (modified or staged). Untracked files cannot be
  # refused: a real libzim build leaves meson's subprojects/googletest-* and
  # subprojects/packagecache/ behind, so a clean-tree rule would reject every
  # re-run. rm -rf the checkout for a guaranteed from-scratch build.
  if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
    echo "$dir has modified tracked files; refusing to build it as '$tag'." >&2
    exit 1
  fi
}

# verify_sha256 <file> <digest> — a file that fails is deleted, so the next
# run downloads afresh instead of tripping over the same bad copy.
verify_sha256() {
  local file=$1 want=$2
  if ! echo "$want  $file" | sha256sum -c - >/dev/null; then
    rm -f "$file"
    echo "$(basename "$file"): sha256 mismatch — removed it, refusing to build" >&2
    exit 1
  fi
}

command -v meson >/dev/null || { echo "meson not found (pip install --user meson ninja)"; exit 1; }
command -v ninja >/dev/null || { echo "ninja not found (pip install --user meson ninja)"; exit 1; }

echo "== zstd 1.5.6 =="
clone_pinned https://github.com/facebook/zstd.git v1.5.6 "$SRC/zstd" "$ZSTD_COMMIT"
make -s -j"$JOBS" -C "$SRC/zstd/lib" libzstd
make -s    -C "$SRC/zstd/lib" PREFIX="$PREFIX" install

echo "== xz / liblzma 5.4.6 (release tarball; pre-backdoor, ships ./configure) =="
# Verified and re-extracted on every run: an xz-5.4.6/ directory left by an
# earlier run was never checked against this digest, and skipping it would
# make the checksum a no-op in the same way a reused clone made the tag one.
[ -f "$SRC/xz.tar.gz" ] || curl -fsSL -o "$SRC/xz.tar.gz" \
  https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz
verify_sha256 "$SRC/xz.tar.gz" "$XZ_SHA256"
rm -rf "$SRC/xz-5.4.6"
tar -C "$SRC" -xzf "$SRC/xz.tar.gz"
( cd "$SRC/xz-5.4.6"
  ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" --disable-static --enable-shared \
    --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-scripts --disable-doc >/dev/null
  make -s -j"$JOBS" && make -s install )

echo "== libzim $LIBZIM_TAG (xapian on, tests off) =="
clone_pinned https://github.com/openzim/libzim.git "$LIBZIM_TAG" "$SRC/libzim" "$LIBZIM_COMMIT"
( cd "$SRC/libzim"
  rm -rf build
  meson setup build --prefix="$PREFIX" --libdir=lib --buildtype=release -Dtests=false -Dwith_xapian=true
  ninja -C build install )

echo "== zimrecreate_libzim harness =="
# shellcheck disable=SC2046  # pkg-config output is a flag list; splitting is the point
g++ -O2 -std=c++17 "$HERE/zimrecreate_libzim.cpp" -o "$BUILD/zimrecreate_libzim" \
  $(pkg-config --cflags --libs libzim)

echo
BUILT=$(pkg-config --modversion libzim)
[ "$BUILT" = "$LIBZIM_TAG" ] || echo "WARNING: built libzim reports $BUILT, tag was $LIBZIM_TAG" >&2
echo "Done. libzim version: $BUILT"
echo "Baseline harness: $BUILD/zimrecreate_libzim"
echo "Run the benchmark with:  PREFIX=$PREFIX LIBZIM=$BUILD/zimrecreate_libzim $HERE/bench.sh SOURCE.zim"
