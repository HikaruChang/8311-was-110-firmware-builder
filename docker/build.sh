#!/bin/sh
# Build in a Debian container. The tree is copied into the container's own
# filesystem first: unsquashfs cannot create device nodes on a Docker Desktop
# bind mount (macOS), and the BSD awk on macOS breaks extract.sh.
#
# Usage: docker/build.sh <version> [out dir]
# Needs stock/V1.0.19_unofficial_WAS_110_PRX126_local.img and stock/PTXG_CX_V0.03/.
set -e
VER=${1:?usage: docker/build.sh <version> [out dir]}
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=${2:-$SRC/out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
# run as the calling user so the output directory stays writable (not as root)
BUILD_UID=$(id -u)
[ "$BUILD_UID" -ne 0 ] || BUILD_UID=1000
docker build -q --build-arg UID="$BUILD_UID" -t 8311-builder "$SRC/docker" >/dev/null
docker run --rm -v "$SRC":/src:ro -v "$OUT":/out 8311-builder bash -c "
	cp -a /src /tmp/w && cd /tmp/w && rm -rf out &&
	./build.sh -i stock/V1.0.19_unofficial_WAS_110_PRX126_local.img -I stock/PTXG_CX_V0.03 --basic --release -V '$VER'
	rc=\$?; cp -a out/. /out/; exit \$rc"
