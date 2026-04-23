#!/bin/bash
# TimelessOS Build System
# Builds the Odin kernel for x86_64 UEFI

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KERNEL_ROOT="$PROJECT_ROOT/kernel"
BUILD_DIR="$PROJECT_ROOT/build"
OUTPUT_DIR="$BUILD_DIR/output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
ARCH="x86_64"
TARGET="freestanding_amd64_sysv"
ODIN_VERSION="dev-2026-04"

# Check for Odin compiler
check_odin() {
    if ! command -v odin &> /dev/null; then
        log_error "Odin compiler not found. Please install Odin from https://odin-lang.org/"
        exit 1
    fi
    log_info "Using Odin: $(odin version)"
}

# Check for required tools
check_tools() {
    local tools=("nasm" "objcopy" "objdump" "ld" "qemu-system-x86_64")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_warn "Tool not found: $tool"
        fi
    done
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

log_info "Building TimelessOS Kernel..."
log_info "Architecture: $ARCH"
log_info "Target: UEFI x86_64"

check_odin
check_tools

# Build UEFI application (kernel)
log_info "Compiling kernel..."

# Odin build command for UEFI freestanding
odin build "$KERNEL_ROOT" \
    -target:$TARGET \
    -out:"$OUTPUT_DIR/TimelessOS.efi" \
    || exit 1

log_info "Kernel built successfully: $OUTPUT_DIR/TimelessOS.efi"

# Generate kernel map file
log_info "Generating kernel map..."
objdump -t "$OUTPUT_DIR/TimelessOS.efi" > "$OUTPUT_DIR/kernel.map" 2>/dev/null || true

# Create ISO for boot testing
log_info "Creating bootable ISO..."

# Create EFI system partition structure
EFI_ROOT="$BUILD_DIR/efi_root"
mkdir -p "$EFI_ROOT/EFI/BOOT"
cp "$OUTPUT_DIR/TimelessOS.efi" "$EFI_ROOT/EFI/BOOT/BOOTX64.EFI"

# Create rEFInd config directory
mkdir -p "$EFI_ROOT/EFI/refind"
cat > "$EFI_ROOT/EFI/refind/refind.conf" << 'EOF'
# rEFInd Configuration for TimelessOS
timeout 5
default_selection "TimelessOS"
scanfor internal,external,optical,manual

# TimelessOS boot entry
menuentry "TimelessOS" {
    icon     /EFI/refined/icons/os_timeless.png
    volume   "EFI"
    loader   /EFI/BOOT/BOOTX64.EFI
    options  "quiet log_level=info"
}
EOF

# Create bootable ISO
xorriso -as mkisofs \
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
    "$EFI_ROOT" \
    -o "$OUTPUT_DIR/timelessos.iso" \
    || log_warn "xorriso not available, ISO not created"

log_info "Build complete!"
log_info "Kernel: $OUTPUT_DIR/TimelessOS.efi"
log_info "ISO: $OUTPUT_DIR/timelessos.iso"

# Run tests if requested
if [ "$1" == "test" ]; then
    log_info "Running kernel tests..."
    # Add test commands here
fi

# Run in QEMU if requested
if [ "$1" == "run" ] || [ "$2" == "run" ]; then
    log_info "Booting in QEMU..."
    qemu-system-x86_64 \
        -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
        -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd \
        -cdrom "$OUTPUT_DIR/timelessos.iso" \
        -m 2048 \
        -smp 2 \
        -serial stdio \
        -display gtk,gl=on \
        -enable-kvm 2>/dev/null || qemu-system-x86_64 \
        -cdrom "$OUTPUT_DIR/timelessos.iso" \
        -m 2048 \
        -smp 2 \
        -serial stdio
fi
