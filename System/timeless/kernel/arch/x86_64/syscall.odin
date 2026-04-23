// SYSCALL/SYSENTER Implementation
// Fast system call interface for x86_64

package arch.x86_64.cpu

import (
    "core:intrinsics"
    "core:log"
)

// MSR Addresses for SYSCALL
MSR_IA32_STAR  :: 0xC0000081  // System Call Target Address Register
MSR_IA32_LSTAR :: 0xC0000082  // Long Mode System Call Target Address
MSR_IA32_FMASK :: 0xC0000084  // System Call Flag Mask

// MSR Addresses for SYSENTER (Intel only)
MSR_IA32_SYSENTER_CS  :: 0x174
MSR_IA32_SYSENTER_ESP :: 0x175
MSR_IA32_SYSENTER_EIP :: 0x176

// Segment Selectors
KERNEL_CS_SELECTOR :: 0x08  // Kernel Code Segment (Ring 0)
USER_CS_SELECTOR   :: 0x1B  // User Code Segment (Ring 3)
KERNEL_SS_SELECTOR :: 0x10  // Kernel Data Segment (Ring 0)
USER_SS_SELECTOR   :: 0x23  // User Data Segment (Ring 3)

// System Call Entry Point (defined in assembly)
extern syscall_entry : $raw(u8)

// Initialize SYSCALL interface
init_syscall :: proc() {
    log.info("Initializing SYSCALL interface...")
    
    // Set LSTAR to syscall entry point
    intrinsics.write_msr(MSR_IA32_LSTAR, cast(u64)(^syscall_entry))
    
    // Set STAR (legacy syscall target)
    // Bits 47:32 = KERNEL_CS, Bits 31:16 = USER_CS
    star_value := (cast(u64)(KERNEL_CS_SELECTOR) << 32) | (cast(u64)(USER_CS_SELECTOR) << 16)
    intrinsics.write_msr(MSR_IA32_STAR, star_value)
    
    // Set FMASK - mask out interrupt flag and other flags during syscall
    // Mask: IF (bit 9), IOPL (bits 12-13), and others
    fmask_value := u64(0x0000000000250202)
    intrinsics.write_msr(MSR_IA32_FMASK, fmask_value)
    
    // Enable SYSCALL in EFER (bit 0)
    efer := intrinsics.read_msr(0xC0000080)
    efer |= 0x1  // Set SCE (System Call Extensions) bit
    intrinsics.write_msr(0xC0000080, efer)
    
    log.info("SYSCALL: LSTAR=0x%X, STAR=0x%X, FMASK=0x%X", 
             intrinsics.read_msr(MSR_IA32_LSTAR),
             intrinsics.read_msr(MSR_IA32_STAR),
             intrinsics.read_msr(MSR_IA32_FMASK))
}

// Initialize SYSENTER (for Intel compatibility)
init_sysenter :: proc(kernel_stack_top: u64, kernel_entry: u64) {
    log.info("Initializing SYSENTER interface...")
    
    // Set SYSENTER CS
    intrinsics.write_msr(MSR_IA32_SYSENTER_CS, cast(u64)(KERNEL_CS_SELECTOR))
    
    // Set SYSENTER ESP (kernel stack)
    intrinsics.write_msr(MSR_IA32_SYSENTER_ESP, kernel_stack_top)
    
    // Set SYSENTER EIP (entry point)
    intrinsics.write_msr(MSR_IA32_SYSENTER_EIP, kernel_entry)
    
    log.info("SYSENTER: CS=0x%X, ESP=0x%X, EIP=0x%X",
             cast(u64)(KERNEL_CS_SELECTOR),
             kernel_stack_top,
             kernel_entry)
}

// Get SYSCALL entry point address
get_syscall_entry :: proc() -> u64 {
    return cast(u64)(^syscall_entry)
}

// Check if SYSCALL is supported
has_syscall :: proc() -> bool {
    _, _, ecx, _ := intrinsics.cpuid(0x80000001, 0)
    return (ecx & (1 << 11)) != 0  // Bit 11 indicates SYSCALL support
}

// Check if SYSENTER is supported
has_sysenter :: proc() -> bool {
    _, _, _, edx := intrinsics.cpuid(1, 0)
    return (edx & (1 << 11)) != 0  // Bit 11 indicates SYSENTER support
}
