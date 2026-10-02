#!/bin/bash
#
# Build AOSP 17 for the Samsung Galaxy S8+ (dream2lte).
#
#   ./build-dream2lte.sh            full build, all CPU threads
#   ./build-dream2lte.sh -j8        limit parallel jobs
#
# Safe to stop at any time (Ctrl-C, or: pkill -INT -f soong_ui); running it
# again resumes where it left off.
#
# Output: out/target/product/dream2lte/{boot-dtbh.img,system.img,vendor.img}

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

LOG=out/build-dream2lte.log
mkdir -p out

source build/envsetup.sh >/dev/null
lunch aosp_dream2lte-cp2a-userdebug >/dev/null

echo "Build started $(date), log: $LOG"
m "$@" 2>&1 | tee "$LOG"

# S-Boot needs the Samsung DTBH device tree injected into the v0 boot image.
OUT_DIR_DEV=out/target/product/dream2lte
python3 device/samsung/universal8895-common/tools/mkbootimg_dtbh.py \
    --boot "$OUT_DIR_DEV/boot.img" \
    --dt device/samsung/dream2lte-kernel/dt.img \
    --max-size 41943040 \
    -o "$OUT_DIR_DEV/boot-dtbh.img" 2>&1 | tee -a "$LOG"

echo "Build finished $(date)" | tee -a "$LOG"
