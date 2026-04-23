# TimelessOS Makefile
# Alternative to build.sh for Unix systems

.PHONY: all clean run debug iso test help

# Configuration
ARCH := x86_64
TARGET := freestanding
ODIN := odin
NASM := nasm
QEMU := qemu-system-x86_64
OBJCOPY := objcopy
OBJDUMP := objdump
XORRISO := xorriso

# Directories
KERNEL_DIR := kernel
BUILD_DIR := build
OUTPUT_DIR := $(BUILD_DIR)/output
EFI_ROOT := $(BUILD_DIR)/efi_root

# Output files
KERNEL_EFI := $(OUTPUT_DIR)/TimelessOS.efi
KERNEL_MAP := $(OUTPUT_DIR)/kernel.map
ISO_FILE := $(OUTPUT_DIR)/timelessos.iso

# Odin collections
COLLECTIONS := \
	-collection:core=$(KERNEL_DIR)/core \
	-collection:mm=$(KERNEL_DIR)/mm \
	-collection:interrupts=$(KERNEL_DIR)/interrupts \
	-collection:drivers=$(KERNEL_DIR)/drivers \
	-collection:services=$(KERNEL_DIR)/services \
	-collection:arch=$(KERNEL_DIR)/arch \
	-collection:lib=$(KERNEL_DIR)/lib

# Odin flags
ODIN_FLAGS := \
	-target:$(ARCH)-$(TARGET) \
	-no-bounds-check \
	-no-rtti \
	-optimization-level:3 \
	-extra-linker-flags:"/SUBSYSTEM:EFI_APPLICATION"

# Default target
all: $(KERNEL_EFI)

# Create directories
$(BUILD_DIR) $(OUTPUT_DIR) $(EFI_ROOT):
	mkdir -p $@

# Build kernel
$(KERNEL_EFI): $(KERNEL_DIR)/main.odin | $(OUTPUT_DIR)
	@echo "Building TimelessOS Kernel..."
	$(ODIN) build $(KERNEL_DIR)/main.odin \
		-out:$@ \
		$(ODIN_FLAGS) \
		$(COLLECTIONS)
	@echo "Kernel built: $@"
	@$(OBJDUMP) -t $@ > $(KERNEL_MAP) 2>/dev/null || true

# Create ISO
iso: $(ISO_FILE)

$(ISO_FILE): $(KERNEL_EFI) | $(EFI_ROOT)
	@echo "Creating bootable ISO..."
	cp $(KERNEL_EFI) $(EFI_ROOT)/EFI/BOOT/BOOTX64.EFI
	mkdir -p $(EFI_ROOT)/EFI/refind
	@echo "timeout 5" > $(EFI_ROOT)/EFI/refind/refind.conf
	@echo "menuentry \"TimelessOS\" {" >> $(EFI_ROOT)/EFI/refind/refind.conf
	@echo "    loader /EFI/BOOT/BOOTX64.EFI" >> $(EFI_ROOT)/EFI/refind/refind.conf
	@echo "}" >> $(EFI_ROOT)/EFI/refind/refind.conf
	$(XORRISO) -as mkisofs \
		-iso-level 3 \
		-rock-ridge \
		-U \
		-V "TIMELESSOS" \
		-eltorito-boot \
		--no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		-efi-boot-part \
		--efi-boot-image \
		--protective-msdos-label \
		$(EFI_ROOT) \
		-o $(ISO_FILE)
	@echo "ISO created: $(ISO_FILE)"

# Run in QEMU
run: $(ISO_FILE)
	@echo "Booting TimelessOS in QEMU..."
	$(QEMU) \
		-cdrom $(ISO_FILE) \
		-m 2048 \
		-smp 2 \
		-serial stdio \
		-display gtk

# Run with UEFI firmware
run-uefi: $(ISO_FILE)
	$(QEMU) \
		-drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
		-drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd \
		-cdrom $(ISO_FILE) \
		-m 2048 \
		-smp 2 \
		-serial stdio

# Debug with GDB
debug: $(ISO_FILE)
	@echo "Starting QEMU with GDB stub..."
	$(QEMU) \
		-cdrom $(ISO_FILE) \
		-m 2048 \
		-s -S \
		-serial stdio
	@echo ""
	@echo "In another terminal, run:"
	@echo "  gdb $(KERNEL_EFI)"
	@echo "  (gdb) target remote :1234"

# Clean build
clean:
	rm -rf $(BUILD_DIR)
	@echo "Build directory cleaned"

# Show help
help:
	@echo "TimelessOS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build kernel (default)"
	@echo "  iso      - Create bootable ISO"
	@echo "  run      - Build and run in QEMU"
	@echo "  run-uefi - Run with OVMF UEFI firmware"
	@echo "  debug    - Start QEMU with GDB stub"
	@echo "  clean    - Remove build files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Usage:"
	@echo "  make          - Build kernel"
	@echo "  make run      - Build and run"
	@echo "  make debug    - Debug with GDB"
	@echo "  make clean    - Clean build"
