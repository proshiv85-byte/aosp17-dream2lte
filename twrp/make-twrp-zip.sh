#!/bin/bash
#
# Package a TWRP-flashable zip from a finished build.
#
#   twrp/make-twrp-zip.sh /path/to/aosp [output dir]
#
# Needs: build-dream2lte.sh output (boot-dtbh.img, system.img, vendor.img),
# simg2img (out/host), aarch64-linux-gnu-gcc, zip.

set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
TOP=$(readlink -f "${1:?usage: $0 <aosp top dir> [output dir]}")
OUT=$(readlink -f "${2:-$TOP/out/target/product/dream2lte}")
PRODUCT=$TOP/out/target/product/dream2lte
SIMG2IMG=$TOP/out/host/linux-x86/bin/simg2img

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

BUILD_ID=$(grep -m1 '^ro.system.build.fingerprint=' "$PRODUCT/system/build.prop" | cut -d= -f2)
DATE=$(date -r "$PRODUCT/system.img" +%Y%m%d-%H%M)
ZIPNAME=aosp17-dream2lte-$DATE.zip

for f in boot-dtbh.img system.img vendor.img; do
    [ -f "$PRODUCT/$f" ] || { echo "missing $PRODUCT/$f; run build-dream2lte.sh" >&2; exit 1; }
done
[ "$(stat -c %Y "$PRODUCT/boot-dtbh.img")" -ge "$(stat -c %Y "$PRODUCT/boot.img")" ] ||
    { echo "boot-dtbh.img is older than boot.img; rerun build-dream2lte.sh" >&2; exit 1; }

echo "== Building sparse_write"
aarch64-linux-gnu-gcc -static -O2 -Wall -o "$STAGE/sparse_write" "$HERE/sparse_write.c"

mkdir -p "$STAGE/META-INF/com/google/android"
sed "s|@BUILD_ID@|$BUILD_ID|" "$HERE/update-binary" > "$STAGE/META-INF/com/google/android/update-binary"
echo "# Dummy file; the installer is update-binary." > "$STAGE/META-INF/com/google/android/updater-script"

cp "$PRODUCT/boot-dtbh.img" "$STAGE/boot.img"
cp "$PRODUCT/system.img" "$PRODUCT/vendor.img" "$STAGE/"

echo "== Checksumming raw partition contents"
{
    printf '%s boot.img %s\n' "$(sha256sum < "$STAGE/boot.img" | cut -d' ' -f1)" "$(stat -c %s "$STAGE/boot.img")"
    for img in system.img vendor.img; do
        "$SIMG2IMG" "$STAGE/$img" "$STAGE/raw"
        printf '%s %s %s\n' "$(sha256sum < "$STAGE/raw" | cut -d' ' -f1)" "$img" "$(stat -c %s "$STAGE/raw")"
        rm "$STAGE/raw"
    done
} > "$STAGE/SHA256SUMS"
cat "$STAGE/SHA256SUMS"

echo "== Zipping"
mkdir -p "$OUT"
rm -f "$OUT/$ZIPNAME"
(cd "$STAGE" && zip -q -r -6 "$OUT/$ZIPNAME" META-INF SHA256SUMS sparse_write boot.img vendor.img system.img)
(cd "$OUT" && sha256sum "$ZIPNAME" > "$ZIPNAME.sha256")
ls -l "$OUT/$ZIPNAME"
echo "Done: $OUT/$ZIPNAME"
