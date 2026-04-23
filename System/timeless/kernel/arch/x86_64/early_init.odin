// Early Initialization - Before Any Allocations
// This runs before the heap, paging, or any complex subsystems

package arch.x86_64.early_init

import (
    "core:intrinsics"
    "core:mem"
)

// Early boot flags
early_boot_complete: bool = false
boot_stage: int = 0


// Initialize early subsystems
// Called immediately after UEFI hands control to the kernel
init :: proc() {
    boot_stage = 1
    
    // Zero out BSS section manually (freestanding)
    zero_bss()
    
    // Set up minimal stack for early boot
    setup_early_stack()
    
    // Disable interrupts during early init
    disable_interrupts()
    
    // Initialize CPU control registers
    init_control_registers()
    
    // Detect CPU and set up features
    detect_cpu_features()
    
    boot_stage = 2
    early_boot_complete = true
}


// Zero BSS Section
// BSS contains uninitialized global/static variables
zero_bss :: proc() {
    extern bss_start: rawptr
    extern bss_end: rawptr
    
    start := uintptr(bss_start)
    end := uintptr(bss_end)
    size := end - start
    
    mem.zero(mem.ptr(start), size)
}


// Set Up Early Stack
// Creates a minimal stack before proper memory management
setup_early_stack :: proc() {
    // Reserve 64KB for early boot stack
    // Located at high memory to avoid conflicts
    EARLY_STACK_SIZE :: 64 * 1024
    EARLY_STACK_BASE :: 0xFFFF_FFFF_FFFF_F000
    
    intrinsics.write_msr(0xC000_0101, EARLY_STACK_BASE) // IA32_GS_BASE
    intrinsics.write_msr(0xC000_0102, EARLY_STACK_BASE) // IA32_Kernel_GS_BASE
    
    // Set RSP
    intrinsics.set_stack_pointer(EARLY_STACK_BASE)
}


// Disable Interrupts
disable_interrupts :: proc() {
    intrinsics.cli()
}


// Initialize Control Registers
init_control_registers :: proc() {
    // CR0: Protection Enable, Write Protect, etc.
    cr0 := intrinsics.read_cr0()
    cr0 |= (1 << 0)  // PE - Protection Enable
    cr0 |= (1 << 16) // WP - Write Protect
    intrinsics.write_cr0(cr0)
    
    // CR4: Enable features like SMEP, SMAP, OSXSAVE
    cr4 := intrinsics.read_cr4()
    cr4 |= (1 << 10)  // OSXSAVE
    cr4 |= (1 << 20)  // SMEP - Supervisor Mode Execution Prevention
    cr4 |= (1 << 21)  // SMAP - Supervisor Mode Access Prevention
    intrinsics.write_cr4(cr4)
    
    // CR3: Will be set by virtual memory manager
    // For now, point to identity-mapped page tables
    setup_identity_page_tables()
}


// Set Up Identity Page Tables
// Temporary 1:1 mapping until virtual memory is ready
setup_identity_page_tables :: proc() {
    // Create minimal PML4, PDPT, PD for identity mapping
    // Maps first 2GB of physical memory
    // This is replaced by proper paging in mm/virtual.odin
    
    extern page_table_base: rawptr
    intrinsics.write_cr3(uintptr(page_table_base))
}


// Detect CPU Features
detect_cpu_features :: proc() {
    // Use CPUID to detect features
    // Store results for later use by cpu package
    eax, ebx, ecx, edx := intrinsics.cpuid(1, 0)
    
    // Check for x86_64 support
    if (edx & (1 << 29)) == 0 {
        // No long mode - fatal error
        halt_cpu("CPU does not support x86_64 long mode")
    }
    
    // Store feature flags
    store_cpu_features(eax, ebx, ecx, edx)
}


// Store CPU Features for Later Use
store_cpu_features :: proc(eax, ebx, ecx, edx: u32) {
    extern cpu_feature_flags: [4]u32
    cpu_feature_flags[0] = eax
    cpu_feature_flags[1] = ebx
    cpu_feature_flags[2] = ecx
    cpu_feature_flags[3] = edx
}


// Halt CPU on Fatal Error
halt_cpu :: proc(reason: string) {
    intrinsics.cli()
    for {
        intrinsics.hlt()
    }
}


// Get Boot Stage
get_boot_stage :: proc() -> int {
    return boot_stage
}


// Is Early Boot Complete
is_complete :: proc() -> bool {
    return early_boot_complete
}
