#!/usr/bin/env bash
# Build the "old fashioned libzim" benchmark baseline from source:
#   zstd 1.5.6 + xz/liblzma 5.4.6 + libzim 9.7.0 (git master) + the
#   zimrecreate_libzim harness, all into a local --prefix. No root needed.
#
# System prerequisites already expected on the host (install via your distro):
#   g++ (C++17), git, curl, pkg-config, libxapian-dev (>=1.4.12), libicu-dev,
#   and meson + ninja (pip install --user meson ninja, or distro packages).
#
# Everything else (zstd/lzma/libzim headers) is built here, because the
# stock distro packages ship only runtime .so's without dev headers.
#
# Usage:   BUILD=/storage/you/zimru-misc-build ./build-baseline.sh
# Output:  $BUILD/prefix/...           (libzim 9.7.0 + deps)
#          $BUILD/zimrecreate_libzim   (the baseline harness binary)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:?set BUILD to a writable dir on a data volume, e.g. /storage/you/zimru-misc-build}
PREFIX=$BUILD/prefix
SRC=$BUILD/src
mkdir -p "$SRC" "$PREFIX"
export PKG_CONFIG_PATH=$PREFIX/lib/x86_64-linux-gnu/pkgconfig:$PREFIX/lib/pkgconfig
JOBS=$(nproc)

command -v meson >/dev/null || { echo "meson not found (pip install --user meson ninja)"; exit 1; }
command -v ninja >/dev/null || { echo "ninja not found (pip install --user meson ninja)"; exit 1; }

echo "== zstd 1.5.6 =="
[ -d "$SRC/zstd" ] || git clone -q --depth 1 --branch v1.5.6 https://github.com/facebook/zstd.git "$SRC/zstd"
make -s -j"$JOBS" -C "$SRC/zstd/lib" libzstd
make -s    -C "$SRC/zstd/lib" PREFIX="$PREFIX" install

echo "== xz / liblzma 5.4.6 (release tarball; pre-backdoor, ships ./configure) =="
if [ ! -d "$SRC/xz-5.4.6" ]; then
  curl -fsSL -o "$SRC/xz.tar.gz" \
    https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz
  tar -C "$SRC" -xzf "$SRC/xz.tar.gz"
fi
( cd "$SRC/xz-5.4.6"
  ./configure --prefix="$PREFIX" --disable-static --enable-shared \
    --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-scripts --disable-doc >/dev/null
  make -s -j"$JOBS" && make -s install )

echo "== libzim 9.7.0 (git master, xapian on, tests off) =="
[ -d "$SRC/libzim" ] || git clone -q --depth 1 https://github.com/openzim/libzim.git "$SRC/libzim"
( cd "$SRC/libzim"
  rm -rf build
  meson setup build --prefix="$PREFIX" --buildtype=release -Dtests=false -Dwith_xapian=true
  ninja -C build install )

echo "== zimrecreate_libzim harness =="
g++ -O2 -std=c++17 "$HERE/zimrecreate_libzim.cpp" -o "$BUILD/zimrecreate_libzim" \
  $(pkg-config --cflags --libs libzim)

echo
echo "Done. libzim version: $(grep -i '^Version' "$PREFIX"/lib/*/pkgconfig/libzim.pc | head -1)"
echo "Baseline harness: $BUILD/zimrecreate_libzim"
echo "Run the benchmark with:  PREFIX=$PREFIX LIBZIM=$BUILD/zimrecreate_libzim $HERE/bench.sh SOURCE.zim"
