# An Alpine-Based Linux Image for Orange Pi RV

A small, experimental Alpine Linux image/build setup for the **Orange Pi RV**, based on the **StarFive JH7110** RISC-V SoC.

This project is my attempt to make the board usable with a lightweight, modern Linux userspace and a much newer kernel than the vendor image provides.

It is also very much a learning project: part Linux hardware bring-up, part OS integration, part “how far can I get this thing using mostly upstream pieces?”


## Why?

Personally, I'm very excited about RISC-V. It's open, interesting, and increasingly practical. The Orange Pi RV is an affordable board (at least it was when I grabbed mine on Amazon).

Unfortunately, the vendor-provided Debian-based image is disappointing to say the least. The image appears to be a highly modified Debian 12 ("Bookworm") image, which is `oldstable` as of June 2026 (not a huge deal, but not exactly new). The included BSP kernel, however, is an elderly 5.15 series, derived from StarFive’s vendor tree. Oh yeah, and it also completely refuses to update cleanly (the repos are broken in such a way that made me want to do this instead).

This is obviously less than ideal in terms of usability and even just exploring the capabilities of the JH7110. Getting a proper upstream kernel running on real RISC-V hardware is a fun and challenging project for experimenting with kernel configuration, boot flow, root filesystems, device trees, firmware quirks, etc.

This is not meant to be a polished distribution, but rather a reproducible starting point for running a modern kernel and userspace on a very specific RISC-V board.

## Current status

The image, in its current incarnation, is intended for a headless Alpine Linux system. Graphical support is currently missing (still waiting on upstream support), which means you will have to use SSH and/or a serial console.

Most of the important low-level pieces are either working or expected to work with the targeted kernel (`7.0.10`). This includes storage, USB, PCIe, Ethernet, clocks, pinctrl, and other basic SoC support.


## What works

The following are known to work, believed to work, or are supported well enough that they should be reasonable to experiment with:

| Feature | Status | Notes |
| --- | --- | --- |
| SD card | Works | SD card boot is the main tested path. |
| NVMe | Works  | Native NVMe booting is supported by the onboard firmware. Under the current kernel config, however, this requires a small initramfs to load the necessary drivers (possible future improvement). |
| Clocks | Works | Required for basic SoC functionality. |
| Pinctrl | Works | Required for most board peripherals. |
| USB | Works | What can I say... it's USB. |
| PCIe | Works | At least NVMe is working. |
| Ethernet | Works | Onboard networking is perfectly usable. |
| WLAN | Works | Yes WiFi works! The `brcmfmac` driver works great, but you need to acquire the proprietary Broadcom firmware blobs for yourself. |
| Sound | Probably works | Kernel support is present, but this is currently untested. |


## What does not work

### Display / HDMI / 3D acceleration

Display output is not currently supported by this image (don't even think about 3D).

As far as I know, the relevant JH7110 display pipeline support is still not fully upstreamed. For now, assume this is a _headless system_ and use serial, SSH, or another non-display workflow.

For upstream status, see: https://rvspace.org/en/project/JH7110_Upstream_Plan

## Usage

The build is driven by the top-level `Makefile`.

To see the available targets:

```sh
make help
```

Current targets:

```text
Targets:
  image           - Build full Alpine disk image
  kernel [JOBS=n] - Build the Linux kernel
  burn DEV=<dev>  - Burn image to target device
  test            - Test image on a live QEMU VM
  clean           - Remove build/
  deepclean       - Remove build/ and staging/
```

### Just tell me what to do!

#### To build the image:
```sh
make
```
This will build the kernel, unpack the Alpine root filesystem, install the kernel modules, copy the boot files, and produce a disk image under `build/`.

#### To burn the image to a disk:
```sh
make burn DEV=<device_path>
```
This will burn the image to a physical disk (probably an SD card). Please do be careful, as this target uses `dd` which operates at the block level, meaning it will summarily _DESTROY ALL EXISTING DATA ON THE DISK_.

#### To test out the disk image:
```sh
make test
```
This spins up a snazzy little RISC-V emulator while keeping the image file in read-only mode, so you can safely test away (requires QEMU RISC-V emulator).

#### To start over without deleting staged resources:

```sh
make clean
make
```

#### To start over completely:

```sh
make deepclean
make
```

## First boot

The default login is:

```text
user: root
password: riscv
```

### SSH
For most network setups (DHCP, nothing weird), you should be able to just plug an Ethernet cable into the board and log in like this (you may have to use the IP address instead):
```sh
ssh root@orangepirv
```

### Serial Connection

A USB-to-UART adapter is highly recommended (there's nothing like seeing those early SBI console messages). The board is preconfigured to spawn a console on `ttyS0`.

To connect via serial (adjust according to your serial adapter):
```sh
screen /dev/ttyUSB0 115200
```
