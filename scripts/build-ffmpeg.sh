#!/usr/bin/env bash
# Build a minimal, arm64-only ffmpeg statically linked with libfdk_aac
# into AudiobookForge/Resources/bin/.
#
# What we get:
#   - ffmpeg only (no ffprobe). AudioProbe parses ffmpeg's stderr banner
#     to read source bitrate; see Services/AudioProbe.swift.
#   - libfdk_aac as the primary AAC encoder. The native `aac` encoder
#     stays compiled in as a fallback.
#   - Only the codecs / demuxers / muxers / parsers / filters / protocols
#     we actually use are enabled. Everything else (x264, x265, lame,
#     network protocols, lavfi video filters, …) is stripped to keep the
#     binary at ~10–12 MB instead of ~130 MB.
#
# Usage:
#   scripts/build-ffmpeg.sh
#
# Idempotent: if the target binary already exists and reports the pinned
# ffmpeg version, the build is skipped. Delete it to force a rebuild.
set -euo pipefail

# ---- pinned versions -------------------------------------------------------

FFMPEG_VERSION="7.1"
FDK_AAC_VERSION="2.0.3"
MACOS_MIN="14.0"

# ---- paths -----------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/AudiobookForge/Resources/bin"
WORK="$ROOT/.build-ffmpeg"
PREFIX="$WORK/prefix"

mkdir -p "$OUT_DIR" "$WORK"

# Skip if the existing binary is the pinned version AND has libfdk_aac.
if [[ -x "$OUT_DIR/ffmpeg" ]] \
   && [[ "$("$OUT_DIR/ffmpeg" -version 2>/dev/null | awk 'NR==1{print $3}')" == "$FFMPEG_VERSION" ]] \
   && "$OUT_DIR/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -qE '^ A.+libfdk_aac'; then
  echo "==> ffmpeg $FFMPEG_VERSION with libfdk_aac already at $OUT_DIR/ffmpeg — nothing to do."
  exit 0
fi
rm -f "$OUT_DIR/ffmpeg"

# ---- toolchain -------------------------------------------------------------

# nasm is needed by fdk-aac's x86 path (not used here on arm64, but the
# configure script still checks for it on macOS unless --disable-asm-x86
# is honoured). We just install it to be safe — fdk-aac is tiny either way.
need_brew=()
for cmd in pkg-config nasm; do
  if ! command -v "$cmd" >/dev/null; then need_brew+=("$cmd"); fi
done
if [[ ${#need_brew[@]} -gt 0 ]]; then
  if ! command -v brew >/dev/null; then
    echo "Homebrew is required to install: ${need_brew[*]}" >&2
    exit 1
  fi
  echo "==> brew install ${need_brew[*]}"
  brew install "${need_brew[@]}" >/dev/null
fi

export CFLAGS="-O3 -arch arm64 -mmacosx-version-min=$MACOS_MIN"
export LDFLAGS="-arch arm64 -mmacosx-version-min=$MACOS_MIN"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

# ---- fdk-aac ---------------------------------------------------------------

if [[ ! -f "$PREFIX/lib/libfdk-aac.a" ]]; then
  echo "==> Building fdk-aac $FDK_AAC_VERSION"
  cd "$WORK"
  tar_name="fdk-aac-$FDK_AAC_VERSION.tar.gz"
  if [[ ! -f "$tar_name" ]]; then
    curl -fsSL "https://downloads.sourceforge.net/opencore-amr/$tar_name" -o "$tar_name"
  fi
  rm -rf "fdk-aac-$FDK_AAC_VERSION"
  tar xf "$tar_name"
  cd "fdk-aac-$FDK_AAC_VERSION"
  ./configure --prefix="$PREFIX" --disable-shared --enable-static \
              CFLAGS="$CFLAGS" >/dev/null
  make -j"$(sysctl -n hw.activecpu)" >/dev/null
  make install >/dev/null
fi

# ---- ffmpeg ----------------------------------------------------------------

echo "==> Building ffmpeg $FFMPEG_VERSION (arm64, libfdk_aac, stripped)"
cd "$WORK"
tar_name="ffmpeg-$FFMPEG_VERSION.tar.xz"
if [[ ! -f "$tar_name" ]]; then
  curl -fsSL "https://ffmpeg.org/releases/$tar_name" -o "$tar_name"
fi
rm -rf "ffmpeg-$FFMPEG_VERSION"
tar xf "$tar_name"
cd "ffmpeg-$FFMPEG_VERSION"

./configure \
  --prefix="$PREFIX" \
  --enable-static --disable-shared \
  --enable-libfdk-aac --enable-nonfree \
  --arch=arm64 --target-os=darwin \
  --extra-cflags="$CFLAGS -I$PREFIX/include" \
  --extra-ldflags="$LDFLAGS -L$PREFIX/lib" \
  --pkg-config-flags="--static" \
  --disable-autodetect \
  --disable-everything \
  --enable-decoder=aac,mp3,alac,flac,opus,vorbis,mjpeg \
  --enable-encoder=aac,libfdk_aac,mjpeg,pcm_s16le \
  --enable-demuxer=mp3,mov,aac,flac,ogg,wav,image2,concat,matroska,ffmetadata \
  --enable-muxer=mp4,ipod,null \
  --enable-parser=aac,mpegaudio \
  --enable-protocol=file,pipe \
  --enable-filter=anull,aresample,atrim,acopy,volume,alimiter,ebur128,acrossfade,format,aformat \
  --enable-bsf=aac_adtstoasc \
  --disable-doc --disable-ffplay --disable-ffprobe --disable-network \
  --disable-debug --enable-small \
  >/dev/null

make -j"$(sysctl -n hw.activecpu)" >/dev/null

# We don't `make install` — that drags ffprobe + manpages in. Just lift
# the one binary we want.
cp -f ffmpeg "$OUT_DIR/ffmpeg"
strip -S -x "$OUT_DIR/ffmpeg"
chmod +x "$OUT_DIR/ffmpeg"

# ---- verify ----------------------------------------------------------------

echo
echo "==> Verifying"
file "$OUT_DIR/ffmpeg"
echo
"$OUT_DIR/ffmpeg" -version | head -1
echo
echo "Encoders (must include libfdk_aac):"
"$OUT_DIR/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -E 'aac|libfdk' || true
echo
echo "Binary size:"
ls -lh "$OUT_DIR/ffmpeg" | awk '{print $5, $9}'
