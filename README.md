# AOSP 17 for the Samsung Galaxy S8+ (Exynos, SM-G955F `dream2lte`)

Plain AOSP (`android-17.0.0_r1`) on the Exynos 8895 Galaxy S8+, running
Samsung's 4.4 kernel with backports. No Lineage branding or Lineage SDK, but
a lot of hardware support is borrowed from LineageOS and the
[universal8895](https://codeberg.org/universal8895) community port.

## Status

Tested on SM-G955F:

| Works | |
|---|---|
| Display, touch, GPU, hardware video decode/encode | yes |
| Wi-Fi, Bluetooth | yes |
| SIM, calls, mobile data, signal | yes |
| Audio, headphone jack, vibration, notification LED | yes |
| Camera (photo + video) | yes |
| Fingerprint, rotation, auto-brightness sensors | yes |
| GPS, NFC | yes |
| USB file transfer (MTP) | yes |
| Charging | yes |
| File-based encryption (PIN + reboot) | yes |

This is a `userdebug` build: `adb root` works.

## Repositories

| Path | Repo |
|---|---|
| `device/samsung/dream2lte` | [android_device_samsung_dream2lte](https://github.com/proshiv85-byte/android_device_samsung_dream2lte) |
| `device/samsung/universal8895-common` | [android_device_samsung_universal8895-common](https://github.com/proshiv85-byte/android_device_samsung_universal8895-common) |
| `device/samsung/dream2lte-kernel` | [android_device_samsung_dream2lte-kernel](https://github.com/proshiv85-byte/android_device_samsung_dream2lte-kernel) (prebuilt Image + DTBH dt.img) |
| `device/samsung_slsi/sepolicy` | [android_device_samsung_slsi_sepolicy](https://github.com/proshiv85-byte/android_device_samsung_slsi_sepolicy) |
| `hardware/samsung` | [android_hardware_samsung](https://github.com/proshiv85-byte/android_hardware_samsung) |
| `hardware/google/pixel` | [android_hardware_google_pixel](https://github.com/proshiv85-byte/android_hardware_google_pixel) |
| `hardware/lineage/compat` | [android_hardware_lineage_compat](https://github.com/proshiv85-byte/android_hardware_lineage_compat) |
| `vendor/samsung` | [proprietary_vendor_samsung](https://github.com/proshiv85-byte/proprietary_vendor_samsung) |
| kernel source | [android_kernel_samsung_universal8895](https://github.com/proshiv85-byte/android_kernel_samsung_universal8895) (branch `aosp17`) |

Changes to AOSP's own projects are kept as patches in [`patches/`](patches)
(bionic, build/make, build/blueprint, frameworks/native, hardware/interfaces,
Connectivity, system/bpf, system/core, libion, vold). They are mostly about
running Android 17 on a 4.4 kernel: BPF kernel-version override and no BPF
ring buffer, fscrypt v1 keyring for vold/init, legacy ION, legacy gralloc in
libui, and compat libraries for the old Samsung vendor blobs.

## Building

Needs a Linux host with about 300 GB free disk and a lot of memory: 32 GB RAM
plus about 36 GB swap was enough (soong peaks around 46 GB).

```sh
mkdir aosp && cd aosp
repo init -u https://android.googlesource.com/platform/manifest -b android-17.0.0_r1 \
    --depth=1 -g default,-darwin,-mips,-device,path:device/google/cuttlefish,platform-linux
git clone https://github.com/proshiv85-byte/aosp17-dream2lte ../aosp17-dream2lte
mkdir -p .repo/local_manifests
cp ../aosp17-dream2lte/local_manifests/dream2lte.xml .repo/local_manifests/
repo sync -c -j4            # googlesource rate-limits; retry on HTTP 429
../aosp17-dream2lte/apply-patches.sh .
cp ../aosp17-dream2lte/*-dream2lte.sh .
./build-dream2lte.sh        # lunch aosp_dream2lte-cp2a-userdebug + m
```

`repo sync` resets the patched AOSP projects, so run `apply-patches.sh`
again after every sync.

The output is `out/target/product/dream2lte/{boot-dtbh.img,system.img,vendor.img}`.
`boot-dtbh.img` is the AOSP boot image with the Samsung DTBH device tree
appended (S-Boot needs it). To rebuild the kernel, see `build-kernel.sh` in
`device/samsung/dream2lte-kernel`.

## Installing

**This wipes the phone.** Back up your EFS partition (IMEI and radio
calibration) first and keep that backup private.

Requirements:
- TWRP.
- The Treble partition layout used by HadesROM (`VENDOR` = `sda18`,
  `SYSTEM` = `sda17`). Flashing stock firmware with Odin restores the stock
  partition layout.
- The `HIDDEN` partition (`sda22`) is used as `/metadata`. It is formatted on
  first boot.

From TWRP, with the phone connected over adb:

```sh
cd out/target/product/dream2lte && mkdir -p flash
simg2img system.img flash/system.raw
simg2img vendor.img flash/vendor.raw
(cd flash && sha256sum system.raw vendor.raw > SHA256SUMS)
adb push boot-dtbh.img /tmp/ && adb shell dd if=/tmp/boot-dtbh.img of=/dev/block/by-name/BOOT
cd - && ./flash-dream2lte.sh      # writes VENDOR + SYSTEM in verified chunks
```

Then in TWRP: Wipe → Format Data (type `yes`), Wipe → Advanced → Cache, and
reboot to System.

## Known quirks

- S-Boot forces SELinux enforcing; the port is fully enforcing.
- If GPS ever reports a position far away, delete
  `/data/vendor/gps/gldata.sto` and `/data/vendor/gps/lto2.dat` as root and
  reboot.

## Credits

- [LineageOS](https://github.com/LineageOS) for the legacy-kernel patches,
  `hardware/samsung`, `hardware/google/pixel` and `hardware/lineage/compat`.
- The [universal8895](https://codeberg.org/universal8895) port (device trees,
  kernel, vendor blobs), including CakesTwix's kernel work.
- Samsung for the kernel source and vendor firmware.
