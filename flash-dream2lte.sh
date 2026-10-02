#!/bin/bash
#
# Flash AOSP 17 vendor + system images to a Galaxy S8+ (dream2lte) in TWRP.
#
# Images are sent in 256 MB chunks through the phone's RAM (/tmp), each chunk
# is written with dd at its exact offset and verified, then the whole
# partition is checksummed. (Streaming over `adb exec-in` truncated the end.)
#
#   ./flash-dream2lte.sh            flash vendor + system
#   ./flash-dream2lte.sh vendor     only vendor
#   ./flash-dream2lte.sh system     only system
#
# BOOT is flashed separately (already done). Does NOT format USERDATA/CACHE:
# do that in TWRP afterwards (Wipe -> Format Data -> "yes", Wipe -> cache).

set -euo pipefail

IMG_DIR="$(dirname "$(readlink -f "$0")")/out/target/product/dream2lte/flash"
CHUNK_MB=256

declare -A DEV=([vendor]=/dev/block/sda18 [system]=/dev/block/sda17)
declare -A NAME=([vendor]=VENDOR [system]=SYSTEM)

die() { echo "ERROR: $*" >&2; exit 1; }

adb get-state 2>/dev/null | grep -q recovery || die "phone is not in TWRP (adb get-state != recovery)"

flash() {
    local part=$1 img="$IMG_DIR/$1.raw" dev=${DEV[$1]}
    [ -f "$img" ] || die "$img not found"

    # Safety: make sure the by-name link points where we think it does.
    local link
    link=$(adb shell readlink -f /dev/block/by-name/${NAME[$part]} | tr -d '\r')
    [ "$link" = "$dev" ] || die "${NAME[$part]} is $link, expected $dev"

    local size chunks
    size=$(stat -c %s "$img")
    chunks=$(( (size + CHUNK_MB*1024*1024 - 1) / (CHUNK_MB*1024*1024) ))
    echo "== $part: $img -> $dev ($size bytes, $chunks chunks)"

    local tmp; tmp=$(mktemp)
    for ((i = 0; i < chunks; i++)); do
        dd if="$img" of="$tmp" bs=1M skip=$((i*CHUNK_MB)) count=$CHUNK_MB status=none
        local want; want=$(sha256sum "$tmp" | cut -d' ' -f1)
        adb push "$tmp" /tmp/chunk.bin >/dev/null
        adb shell "dd if=/tmp/chunk.bin of=$dev bs=1M seek=$((i*CHUNK_MB)) conv=notrunc,fsync 2>/dev/null; rm /tmp/chunk.bin"
        local len; len=$(stat -c %s "$tmp")
        local got; got=$(adb shell "dd if=$dev bs=1M skip=$((i*CHUNK_MB)) count=$CHUNK_MB 2>/dev/null | head -c $len | sha256sum" | cut -d' ' -f1)
        [ "$want" = "$got" ] || die "$part chunk $i verify failed"
        printf '  chunk %d/%d ok\n' $((i+1)) "$chunks"
    done
    rm -f "$tmp"

    adb shell sync
    local want got
    want=$(grep " $part.raw\$" "$IMG_DIR/SHA256SUMS" | cut -d' ' -f1)
    got=$(adb shell "sha256sum $dev" | cut -d' ' -f1)
    [ "$want" = "$got" ] || die "$part full verify failed ($got != $want)"
    echo "== $part OK ($got)"
}

parts=("${@:-vendor system}")
for p in ${parts[@]}; do flash "$p"; done
echo "Done. Now in TWRP: Wipe -> Format Data -> type yes; Wipe -> Advanced -> Cache; then Reboot -> System."
