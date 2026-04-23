// Odin Build Configuration for TimelessOS
// Use with: odin build kernel/main.odin -build-config:build_config.odin

package main

// Target configuration
TARGET_ARCH :: "x86_64"
TARGET_OS :: "freestanding"
TARGET_ABI :: "uefi"

// Build flags
OPTIMIZATION_LEVEL :: 3  // 0=none, 1=minimal, 2=normal, 3=aggressive
DEBUG_INFO :: false       // Set true for debugging
BOUNDS_CHECK :: false     // Disable bounds checking for performance
RTTI :: false             // Disable runtime type information

// Memory settings
KERNEL_BASE :: 0xFFFF_8000_0000_0000
KERNEL_HEAP_SIZE :: 256 * 1024 * 1024  // 256MB
KERNEL_STACK_SIZE :: 64 * 1024  // 64KB per CPU

// Feature flags
ENABLE_SMP :: false         // Multi-core support
ENABLE_APIC :: true         // APIC interrupt controller
ENABLE_ACPI :: true         // ACPI power management
ENABLE_PCI :: true          // PCI enumeration
ENABLE_USB :: false         // USB support (in progress)
ENABLE_NETWORK :: false     // Network stack (in progress)

// Driver configuration
ENABLE_GPU_INTEL :: true
ENABLE_GPU_AMD :: true
ENABLE_GPU_NVIDIA_OPEN :: true
ENABLE_GPU_NVIDIA_PROPRIETARY :: true
ENABLE_GPU_VIRTUAL :: true

ENABLE_SERIAL :: true
ENABLE_VGA :: true
ENABLE_KEYBOARD :: true
ENABLE_MOUSE :: true

// Service configuration
DEFAULT_BOOT_TARGET :: "multi-user"
MAX_SERVICES :: 64
SERVICE_TIMEOUT :: 30  // seconds

// Logging
LOG_LEVEL :: 2  // 0=none, 1=error, 2=info, 3=debug, 4=trace
LOG_SERIAL :: true
LOG_VGA :: true

// Build collections
COLLECTIONS :: [][2]string = {
    {"core", "kernel/core"},
    {"mm", "kernel/mm"},
    {"interrupts", "kernel/interrupts"},
    {"drivers", "kernel/drivers"},
    {"services", "kernel/services"},
    {"arch", "kernel/arch"},
    {"lib", "kernel/lib"},
}

// Linker flags
LINKER_FLAGS :: []string = {
    "/SUBSYSTEM:EFI_APPLICATION",
    "/ENTRY:efi_main",
    "/BASE:0x10000",
    "/ALIGN:4096",
}

// Extra compiler flags
EXTRA_FLAGS :: []string = {
    "-no-bounds-check",
    "-no-rtti",
    "-use-llvm",
    "-llvm-args:-O3",
}

// Output configuration
OUTPUT_NAME :: "TimelessOS.efi"
OUTPUT_DIR :: "build/output"
MAP_FILE :: "build/output/kernel.map"
