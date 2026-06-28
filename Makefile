# Overridable compiler options
CROSS_COMPILE ?= riscv64-linux-gnu-
JOBS          ?= $(shell nproc)

# Kernel version to download and build for the image
KERNEL_VER    := 7.0.10

# Input file paths (don't mess with these)
KERNEL_CFG    := $(CURDIR)/orangepirv_defconfig
INITRD_TAR    := $(CURDIR)/initrd/busybox-base.tar.gz
INITRD_INI    := $(CURDIR)/initrd/init
ROOTFS_TAR    := $(CURDIR)/alpine-rootfs.tar.gz

# Output paths
OUTPUT_DIR    := $(CURDIR)/output
KERNEL_SRC    := $(OUTPUT_DIR)/linux-$(KERNEL_VER)
KERNEL_IMG    := $(KERNEL_SRC)/arch/riscv/boot/Image
KERNEL_DTB    := $(KERNEL_SRC)/arch/riscv/boot/dts/starfive/jh7110-orangepi-rv.dtb
INITRD_TMP    := $(OUTPUT_DIR)/initrd
INITRD_IMG    := $(OUTPUT_DIR)/uInitrd

# Final disk image settings
DISK_IMAGE    := $(OUTPUT_DIR)/alpine-orangepirv.img
DISK_SIZE     := 500M
BOOT_SIZE     := 100M

# Extra Linux kernel parameters ('root=' is added implicitly)
LINUX_CMD     := earlycon console=ttyS0,115200 modules=clk-starfive-jh7110-aon,clk-starfive-jh7110-stg,phy-jh7110-pcie,pcie-starfive,nvme

# build-initrd parameters
INITR_ENV=\
  KERNEL_SRC='$(KERNEL_SRC)' \
  INITRD_TAR='$(INITRD_TAR)' \
  INITRD_INI='$(INITRD_INI)' \
  INITRD_TMP='$(INITRD_TMP)' \
  INITRD_IMG='$(INITRD_IMG)'

# build-image parameters
BUILD_ENV=\
  ROOTFS_TAR='$(ROOTFS_TAR)' \
  KERNEL_SRC='$(KERNEL_SRC)' \
  KERNEL_IMG='$(KERNEL_IMG)' \
  KERNEL_DTB='$(KERNEL_DTB)' \
  INITRD_IMG='$(INITRD_IMG)' \
  DISK_IMAGE='$(DISK_IMAGE)' \
  DISK_SIZE='$(DISK_SIZE)' \
  BOOT_SIZE='$(BOOT_SIZE)' \
  LINUX_CMD='$(LINUX_CMD)'

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

# Remove eveything but kernel
.PHONY: clean
clean:
	@find $(OUTPUT_DIR) -mindepth 1 ! -path '*linux-*' -delete

.PHONY: deepclean
deepclean:
	@rm -rf $(OUTPUT_DIR)

$(OUTPUT_DIR):
	@mkdir -p "$@"

$(KERNEL_SRC).tar.xz: | $(OUTPUT_DIR)
	@version='$(KERNEL_VER)'; \
	major="$${version%%.*}"; \
	wget "https://cdn.kernel.org/pub/linux/kernel/v$${major}.x/linux-$${version}.tar.xz" -O "$@"

$(KERNEL_SRC)/.extracted: $(KERNEL_SRC).tar.xz
	@tar -C $(OUTPUT_DIR) -xf $(KERNEL_SRC).tar.xz
	@touch "$@"

$(KERNEL_SRC)/.config: $(KERNEL_SRC)/.extracted $(KERNEL_CFG)
	@cp -v $(KERNEL_CFG) $(KERNEL_SRC)/.config
	@$(MAKE) -C $(KERNEL_SRC) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig

$(KERNEL_IMG) $(KERNEL_DTB) &: $(KERNEL_SRC)/.config
	@$(MAKE) -C $(KERNEL_SRC) -j$(JOBS) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) Image modules dtbs

$(INITRD_IMG): $(INITRD_TAR) $(INITRD_INI) $(KERNEL_IMG)
	env $(INITR_ENV) ./build-initrd

$(DISK_IMAGE): Makefile build-image $(KERNEL_IMG) $(KERNEL_DTB) $(INITRD_IMG) $(ROOTFS_TAR) | $(OUTPUT_DIR)
	sudo env $(BUILD_ENV) ./build-image
