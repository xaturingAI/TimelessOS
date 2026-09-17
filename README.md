# TimelessOS
A vibe code OS, that I'm working on hand coding out  once i have the basic layout of the kernel made in Odin 


TimelessOS

A 64-bit UEFI-based operating system written in Odin.
Overview

Timeless OS is a modern x86_64 kernel featuring:

    UEFI Boot - Boots via rEFInd bootloader
    Odin Language - Primary kernel language for safety and clarity
    Modular GPU Drivers - Support for Intel, AMD, NVIDIA (open & proprietary), and virtual GPUs
    Service Manager - Dinit-based init system
    Full Interrupt Handling - PIC and APIC support
    Memory Management - Physical frame allocator, virtual memory, kernel heap

Project Structure

'' timeless-os/ '' 
├── boot/                    # Boot-related files

**├── kernel/
│   ├── main.odin           # Kernel entry point
│   ├── core/               # Core kernel utilities
│   ├── mm/                 # Memory management
│   │   ├── physical.odin   # Physical frame allocator
│   │   ├── virtual.odin    # Virtual memory/paging
│   │   └── heap.odin       # Kernel heap

│   ├── interrupts/         # Interrupt handling
│   │   ├── idt.odin        # IDT setup
│   │   ├── pic.odin        # PIC controller
│   │   └── apic.odin       # APIC controller**

│   ├── drivers/            # Device drivers
│   │   ├── serial/uart.odin    # Serial console
│   │   ├── video/vga.odin      # VGA text mode
│   │   ├── input/              # Input devices
│   │   │   ├── keyboard.odin
│   │   │   └── mouse.odin
│   │   └── gpu/                # Graphics drivers
│   │       ├── gpu.odin        # GPU framework
│   │       ├── intel/          # Intel graphics
│   │       ├── amd/            # AMD graphics
│   │       ├── nvidia-open/    # Nouveau-style
│   │       ├── nvidia-proprietary/
│   │       └── virtual/        # VM graphics


│   ├── services/           # System services
│   │   └── dinit.odin      # Init system
│   ├── arch/x86_64/        # Architecture-specific code
│   │   ├── cpu.odin
│   │   ├── io.odin
│   │   └── early_init.odin
│   └── lib/                # Kernel libraries
├── build/                  # Build output
├── scripts/                # Build scripts
└── docs/                   # Documentation '' 

Requirements
Build Tools

    Odin compiler (latest dev version)
    NASM (for any assembly stubs)
    binutils (objcopy, objdump)
    xorriso (for ISO creation)
    QEMU (for testing)

UEFI Environment

    OVMF/EDK II UEFI firmware (for QEMU)
    rEFInd bootloader

Building

cd timeless-os/build
chmod +x build.sh

# Build kernel
./build.sh

# Build and run in QEMU
./build.sh run

Boot Process

    UEFI Firmware initializes hardware
    rEFInd loads TimelessOS.efi
    efi_main() entry point in kernel/main.odin
    Early Init - CPU, stack, basic setup
    Memory Management - Physical, virtual, heap
    Interrupts - IDT, PIC, APIC
    Drivers - Serial, VGA, keyboard, mouse, GPU
    Services - Dinit starts system services

Memory Layout

0x0000_0000_0000_0000 - 0x0000_7FFF_FFFF_FFFF  User Space
0xFFFF_8000_0000_0000 - 0xFFFF_FFFF_FFFF_FFFF  Kernel Space
  ├─ Kernel Image
  ├─ Kernel Heap
  ├─ Kernel Stacks
  ├─ MMIO Regions
  └─ Physical Mapping (direct 1:1)

Interrupt Layout

0-31:   CPU Exceptions
32-47:  Hardware IRQs (PIC remapped)
48-255: Software interrupts, APIC, custom

Supported Hardware
GPUs

    Intel HD Graphics, Iris, UHD (Gen8+)
    AMD Radeon (GCN, RDNA, RDNA2, RDNA3)
    NVIDIA (Kepler through Ada, open & proprietary)
    VirtualBox SVGA
    QEMU VirtIO-GPU
    VMware SVGA II

Input

    PS/2 Keyboard
    PS/2 Mouse
    Serial (UART 16550A)

Service Manager (Dinit)

Services are defined with dependencies and restart policies:

register_service(Service{
    name = "sshd",
    command = "/sbin/sshd",
    dependencies = {"network"},
    restart_policy = .Always,
})

Boot Targets

    emergency - Minimal single-user
    rescue - Recovery mode
    multi-user - Full CLI, no GUI
    graphical - Full GUI with display manager

Kernel Modules (dr-kmod)

Graphics drivers can be loaded as kernel modules:

    drm-kmod-intel
    drm-kmod-amd
    nvidia-kmod
    nvidia-open-kmod
    virtio-gpu-kmod

Debugging
Serial Console

qemu-system-x86_64 \
    -cdrom timelessos.iso \
    -serial stdio \
    -m 2048

GDB Debugging

qemu-system-x86_64 \
    -cdrom timelessos.iso \
    -s -S  # Wait for GDB

gdb build/output/TimelessOS.efi
(gdb) target remote :1234

License

TimelessOS is provided as-is for educational and development purposes.
Contributing

    Fork the repository
    Create a feature branch
    Follow Odin style guidelines
    Test in QEMU before submitting
    Document new drivers/features

Status

Alpha - Core subsystems implemented, driver framework in place.
Implemented

    UEFI bootstrap
    Physical memory manager
    Virtual memory (4-level paging)
    Kernel heap
    IDT and exception handling
    PIC and APIC
    Serial UART driver
    VGA text mode
    PS/2 keyboard/mouse
    GPU driver framework
    Dinit service manager

In Progress

    Full Intel GPU acceleration
    AMDGPU driver
    USB support
    Network drivers
    Filesystem (VFS, ext4, FAT32)

Planned

    SMP support
    User mode processes
    Syscall interface
    POSIX compatibility layer
