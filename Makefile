# Overridable compiler options
CROSS_COMPILE ?= riscv64-linux-gnu-
JOBS          ?= $(shell nproc)

# Kernel version to download and build for the image
# Change this if you're feeling adventurous, and/or
# are prepared to mess with the config.
KERNEL_VER    := 7.0.10

# File names and paths (don't mess with these)
BUILD_DIR     := build
STAGE_DIR     := staging
KERNEL_CFG    := orangepirv_defconfig
ROOTFS_TAR    := alpine-rootfs.tar.gz
KERNEL_SRC    := $(STAGE_DIR)/linux-$(KERNEL_VER)
KERNEL_IMG    := $(KERNEL_SRC)/arch/riscv/boot/Image
KERNEL_DTB    := $(KERNEL_SRC)/arch/riscv/boot/dts/starfive/jh7110-orangepi-rv.dtb

# Final disk image settings
DISK_IMAGE    := $(BUILD_DIR)/alpine-orangepirv.img
DISK_SIZE     := 500M
BOOT_SIZE     := 100M

# Extra Linux kernel parameters ('root=' is derived/added implicitly)
BOOT_APPEND   := rootwait earlycon console=ttyS0,115200

# Variables passed to build-image script
BUILD_ENV=\
  ROOTFS_TAR='$(ROOTFS_TAR)' \
  KERNEL_SRC='$(KERNEL_SRC)' \
  KERNEL_IMG='$(KERNEL_IMG)' \
  KERNEL_DTB='$(KERNEL_DTB)' \
  DISK_IMAGE='$(DISK_IMAGE)' \
  DISK_SIZE='$(DISK_SIZE)' \
  BOOT_SIZE='$(BOOT_SIZE)' \
  BOOT_APPEND='$(BOOT_APPEND)'

.PHONY: all
all: image

.PHONY: help
help:
	@echo "Targets:"
	@echo "  image           - Build full Alpine disk image"
	@echo "  kernel [JOBS=n] - Build the Linux kernel"
	@echo "  burn DEV=<dev>  - Burn image to target device"
	@echo "  test            - Test image on a live QEMU VM"
	@echo "  clean           - Remove build/"
	@echo "  deepclean       - Remove build/ and staging/"

.PHONY: image
image: $(DISK_IMAGE)

.PHONY: kernel
kernel: $(KERNEL_IMG) $(KERNEL_DTB)

.PHONY: burn
burn: image
	@test -n "$(DEV)" || { echo "Usage: make burn DEV=/dev/sdX" >&2; exit 1; }
	sudo ./burn-image "$(DISK_IMAGE)" "$(DEV)"

# Spin up a minimal VM while keeping the underlying image read only
.PHONY: test
test: image
	qemu-system-riscv64 \
	  -M virt -smp 4 -m 1G \
	  -snapshot -nographic \
	  -kernel "$(KERNEL_IMG)" \
	  -netdev user,id=net0 \
	  -device virtio-net-device,netdev=net0  \
	  -drive "file=$(DISK_IMAGE),format=raw,if=virtio" \
	  -append "console=ttyS0 root=/dev/vda2 ro"

.PHONY: clean
clean:
	@rm -rf build/ 

.PHONY: deepclean
deepclean:
	@rm -rf build/ staging/

$(BUILD_DIR):
	@mkdir -p "$@"

$(STAGE_DIR):
	@mkdir -p "$@"

$(KERNEL_SRC).tar.xz: | $(STAGE_DIR)
	@version='$(KERNEL_VER)'; \
	major="$${version%%.*}"; \
	wget "https://cdn.kernel.org/pub/linux/kernel/v$${major}.x/linux-$${version}.tar.xz" -O "$@"

$(KERNEL_SRC)/.extracted: $(KERNEL_SRC).tar.xz
	@tar -C $(STAGE_DIR) -xf $(KERNEL_SRC).tar.xz
	@touch "$@"

$(KERNEL_SRC)/.config: $(KERNEL_SRC)/.extracted $(KERNEL_CFG)
	@cp -v $(KERNEL_CFG) $(KERNEL_SRC)/.config
	@$(MAKE) -C $(KERNEL_SRC) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig

$(KERNEL_IMG) $(KERNEL_DTB) &: $(KERNEL_SRC)/.config
	@$(MAKE) -C $(KERNEL_SRC) -j$(JOBS) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) Image modules dtbs

$(DISK_IMAGE): Makefile build-image $(KERNEL_IMG) $(KERNEL_DTB) $(ROOTFS_TAR) | $(BUILD_DIR)
	sudo env $(BUILD_ENV) ./build-image
