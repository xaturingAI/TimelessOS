// TimelessOS Kernel - Main Entry Point
// UEFI x86_64 Bootstrap

package main

import (
    "core:log"
    "core:panic"
    "arch:x86_64/cpu"
    "mm:physical"
    "mm:virtual"
    "mm:heap"
    "interrupts:idt"
    "interrupts:pic"
    "interrupts:apic"
    "drivers:serial/uart"
    "drivers:video/vga"
    "drivers:input/keyboard"
    "drivers:input/mouse"
    "drivers:network"
    "filesystem:vfs"
    "filesystem:fat32"
    "filesystem:ext4"
    "filesystem:xfs"
    "filesystem:zfs"
    "services:dinit"
    "scheduler"
)

// UEFI Entry Point
// Called by UEFI firmware after loading the EFI application
@(entry_point)
efi_main :: proc(handle: rawptr, system_table: rawptr) -> c.int {
    // Early initialization - before any allocations
    early_init.init()
    
    // Initialize serial console for early debug output
    uart.init_console()
    log.set_level(.INFO)
    
    log.info("TimelessOS Kernel Starting...")
    log.info("UEFI Handle: %p", handle)
    log.info("System Table: %p", system_table)
    
    // Initialize CPU features
    cpu.init()
    log.info("CPU: %s", cpu.get_model_name())
    log.info("Features: %s", cpu.get_features_string())
    
    // Initialize physical memory manager
    // Parse UEFI memory map and set up frame allocator
    physical.init(system_table)
    log.info("Physical Memory: %d MB available", physical.get_available_memory() / (1024 * 1024))
    
    // Set up paging and virtual memory
    virtual.init()
    log.info("Virtual Memory: Page tables initialized")
    
    // Initialize kernel heap
    heap.init()
    log.info("Kernel Heap: Initialized at %p", heap.get_base())
    
    // Initialize interrupt handling
    idt.init()
    log.info("IDT: 256 entries configured")
    
    pic.init()
    log.info("PIC: Legacy interrupt controller configured")
    
    apic.init()
    log.info("APIC: Local and I/O APIC initialized")
    
    // Enable interrupts
    cpu.enable_interrupts()
    log.info("Interrupts: Enabled")
    
    // Initialize scheduler (before drivers that might block)
    scheduler.init()
    log.info("Scheduler: Process scheduler initialized")
    
    // Initialize basic drivers
    vga.init()
    log.info("VGA: Text mode initialized (80x25)")
    
    keyboard.init()
    log.info("Keyboard: PS/2 controller initialized")
    
    mouse.init()
    log.info("Mouse: PS/2 mouse initialized")
    
    // Initialize graphics drivers (modular)
    // These are loaded as kernel modules based on detected hardware
    log.info("GPU: Detecting hardware...")
    init_gpu_drivers()
    
    // Initialize filesystem layer
    log.info("VFS: Initializing virtual filesystem...")
    vfs.vfs_init()
    
    // Register filesystem drivers
    log.info("VFS: Registering filesystem drivers...")
    register_filesystem_drivers()
    
    // Initialize service manager
    dinit.init()
    log.info("Dinit: Service manager initialized")
    
    // Initialize network stack
    log.info("Network: Initializing network stack...")
    init_network_stack()
    
    // Initialize syscall interface (for user-space communication)
    cpu.init_syscall()
    log.info("SYSCALL: Fast system call interface initialized")
    
    // Initialize TSS for hardware stack switching
    kernel_stack_top := cast(u64)(heap.get_base()) - 1
    cpu.init_tss(kernel_stack_top)
    log.info("TSS: Task State Segment initialized")
    
    // Load kernel modules
    load_kernel_modules()
    
    // Start user-space init
    log.info("Kernel initialization complete")
    log.info("Starting user-space environment...")
    
    // Create first user process (init)
    // Load and execute /sbin/init from filesystem
    log.info("Loading init process from /sbin/init...")
    load_init_process()
    
    // Enter main scheduler loop
    // The idle thread will run when no other threads are ready
    scheduler.run()
    
    return 0
}


// Load Init Process from ELF Binary
// Loads /sbin/init or /bin/init from filesystem using ELF loader
load_init_process :: proc() {
    log.info("ELF Loader: Attempting to load init process...")
    
    // Try multiple init paths
    init_paths := ["/sbin/init", "/bin/init", "/init"]
    
    for path in init_paths {
        log.info("ELF Loader: Trying %s...", path)
        
        // Create user process from ELF binary using our new process management
        pid := kernel.create_user_process(path, {})
        
        if pid != 0 {
            log.info("ELF Loader: Successfully loaded %s (PID=%d)", path, pid)
            return
        }
    }
    
    // If no init binary found, create a minimal test process
    log.warn("ELF Loader: No init binary found, creating test process...")
    create_test_process()
}

// Create Test Process (fallback if no init binary)
create_test_process :: proc() {
    log.info("Creating minimal test process...")
    
    // For now, just create a kernel thread as a placeholder
    // In the future, this could create a minimal ELF in-memory
    log.warn("Test process creation not fully implemented")
}

// GPU Driver Initialization
// Detects hardware and loads appropriate driver
init_gpu_drivers :: proc() {
    // Detect GPU hardware via PCI enumeration
    gpu_vendor, device_id := pci_detect_gpu()
    
    switch gpu_vendor {
    case .Intel:
        log.info("GPU: Intel Integrated Graphics detected (0x%04X)", device_id)
        drivers.gpu.intel.init(device_id)
        
    case .AMD:
        log.info("GPU: AMD/ATI Graphics detected (0x%04X)", device_id)
        drivers.gpu.amd.init(device_id)
        
    case .NVIDIA_Proprietary:
        log.info("GPU: NVIDIA (Proprietary driver) detected (0x%04X)", device_id)
        drivers.gpu.nvidia_proprietary.init(device_id)
        
    case .NVIDIA_Open:
        log.info("GPU: NVIDIA (Open source driver) detected (0x%04X)", device_id)
        drivers.gpu.nvidia_open.init(device_id)
        
    case .VirtualBox:
        log.info("GPU: VirtualBox SVGA detected")
        drivers.gpu.virtual.virtualbox.init()
        
    case .QEMU:
        log.info("GPU: QEMU VirtIO-GPU detected")
        drivers.gpu.virtual.qemu.init()
        
    case:
        log.warn("GPU: Unknown or unsupported device (0x%04X)", device_id)
        log.info("GPU: Falling back to VGA text mode")
    }
}


// Filesystem Driver Registration
register_filesystem_drivers :: proc() {
    // FAT32 - EFI system partition support
    log.info("VFS: Registering FAT32 driver...")
    vfs.vfs_register_fs("fat32", &fat32.fat32_fs_ops, &fat32.fat32_file_ops)
    
    // ext4 - Primary Linux filesystem
    log.info("VFS: Registering ext4 driver...")
    vfs.vfs_register_fs("ext4", &ext4.ext4_fs_ops, &ext4.ext4_file_ops)
    
    // XFS - High-performance filesystem
    log.info("VFS: Registering XFS driver...")
    vfs.vfs_register_fs("xfs", &xfs.xfs_fs_ops, &xfs.xfs_file_ops)
    
    // ZFS - Advanced COW filesystem (stub)
    log.info("VFS: Registering ZFS driver (stub)...")
    vfs.vfs_register_fs("zfs", &zfs.zfs_fs_ops, &zfs.zfs_file_ops)
    
    log.info("VFS: %d filesystem drivers registered", 4)
}


// Network Stack Initialization
init_network_stack :: proc() {
    // Initialize TCP/IP stack
    if !drivers.network.network_stack_init() {
        log.error("Network: Stack initialization failed")
        return
    }
    
    // Detect and initialize network hardware
    // This would enumerate PCI devices and find network cards
    log.info("Network: Detecting network hardware...")
    
    // Example: Initialize e1000 if found
    // e1000_mmio := pci_find_device(0x8086, 0x100E)  // Intel e1000
    // if e1000_mmio != 0 {
    //     if drivers.network.e1000_init(e1000_mmio) {
    //         log.info("Network: e1000 initialized")
    //         
    //         // Configure network (DHCP or static)
    //         if !drivers.network.network_dhcp() {
    //             log.warn("Network: DHCP failed, using static config")
    //         }
    //     }
    // }
    
    // Example: Initialize VirtIO-Net if found
    // virtio_mmio := pci_find_device(0x1AF4, 0x1000)  // VirtIO Network
    // if virtio_mmio != 0 {
    //     if drivers.network.virtio_net_init(virtio_mmio) {
    //         log.info("Network: VirtIO-Net initialized")
    //     }
    // }
    
    log.info("Network: Initialization complete")
}


// PCI GPU Detection
pci_detect_gpu :: proc() -> (GPU_Vendor, u16) {
    // Scan PCI bus for VGA/Display controllers
    // Returns vendor type and device ID
    // Implementation in drivers/gpu/pci_detect.odin
    return .Unknown, 0
}


// Kernel Module Loading
load_kernel_modules :: proc() {
    // Load dr-kmod graphics modules
    // Modules are signed and verified before loading
    modules := [
        "drm-kmod-intel",
        "drm-kmod-amd",
        "nvidia-kmod",
        "nvidia-open-kmod",
        "virtio-gpu-kmod",
    ]
    
    for _, module in modules {
        if module_exists(module) {
            log.info("Loading kernel module: %s", module)
            load_module(module)
        }
    }
}


// Main Kernel Loop (deprecated - scheduler handles this now)
kernel_main_loop :: proc() {
    // This function is kept for compatibility but is no longer used
    // The scheduler's idle thread now handles CPU idle time
    for {
        cpu.halt()
    }
}

// Create First User Process (DEPRECATED - Use ELF Loader Instead)
// This function is kept for historical reference only
// Sets up initial user-space process with proper privilege levels
create_first_user_process :: proc() {
    log.warn("create_first_user_process is deprecated, use load_init_process instead")
    load_init_process()
}

// Kernel Panic Handler
#[no_return]
kernel_panic :: proc(message: string, #private location: runtime.Source_Location) {
    log.error("KERNEL PANIC at %s:%d", location.file, location.line)
    log.error("Reason: %s", message)
    
    // Disable interrupts
    cpu.disable_interrupts()
    
    // Display panic screen
    vga.display_panic(message, location)
    
    // Halt CPU
    for {
        cpu.halt()
    }
}
