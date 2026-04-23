// Task State Segment (TSS) Implementation
// Required for hardware stack switching on privilege level changes

package arch.x86_64.cpu

import (
    "core:intrinsics"
    "core:types"
)

// TSS Structure as defined by x86_64 architecture
TSS :: struct {
    reserved1      : u32,
    rsp0           : u64, // Kernel Stack Pointer (Ring 0)
    rsp1           : u64,
    rsp2           : u64,
    reserved2      : u64,
    ist1           : u64, // Interrupt Stack Table 1
    ist2           : u64,
    ist3           : u64,
    ist4           : u64,
    ist5           : u64,
    ist6           : u64,
    ist7           : u64,
    reserved3      : u64,
    reserved4      : u64,
    io_map_base    : u16,
}

// Global TSS instance
tss_instance : TSS
tss_initialized : bool = false

// Initialize the TSS with kernel stack pointers
init_tss :: proc(kernel_stack_top: u64) {
    tss_instance = TSS{
        reserved1 = 0,
        rsp0 = kernel_stack_top, // Critical: CPU switches to this stack on interrupt from user mode
        rsp1 = 0,
        rsp2 = 0,
        reserved2 = 0,
        ist1 = 0,
        ist2 = 0,
        ist3 = 0,
        ist4 = 0,
        ist5 = 0,
        ist6 = 0,
        ist7 = 0,
        reserved3 = 0,
        reserved4 = 0,
        io_map_base = 0,
    }

    // Load TR register with TSS selector (0x28 = GDT entry 5, TI=0, RPL=0)
    load_tr(0x28)
    
    tss_initialized = true
}

// Load TR register (Assembly helper)
load_tr :: proc(selector: u16) {
    asm {
        mov ax, selector
        ltr ax
    }
}

// Get current TSS pointer (for debugging or updates)
get_tss_ptr :: proc() -> ^TSS {
    return &tss_instance
}

// Update kernel stack pointer in TSS (called during context switch)
update_kernel_stack :: proc(new_stack_top: u64) {
    tss_instance.rsp0 = new_stack_top
}

// Check if TSS is initialized
is_tss_initialized :: proc() -> bool {
    return tss_initialized
}
