// Core CPU Utilities
// x86_64 CPU features and control

package arch.x86_64.cpu

import (
    "core:intrinsics"
    "core:log"
)

// CPU Features
CPU_FEATURES :: enum {
    FPU,
    VME,
    DE,
    PSE,
    TSC,
    MSR,
    PAE,
    MCE,
    CX8,
    APIC,
    SEP,
    MTRR,
    PGE,
    MCA,
    CMOV,
    PAT,
    PSE36,
    CLFLUSH,
    MMX,
    FXSR,
    SSE,
    SSE2,
    SSE3,
    SSSE3,
    SSE4_1,
    SSE4_2,
    AVX,
    AVX2,
    AVX512,
    SMEP,
    SMAP,
    NX,
    LM,  // Long Mode (x86_64)
}

// CPU State
cpu_initialized: bool = false
cpu_vendor: string = ""
cpu_brand: string = ""
cpu_features: u64 = 0
cpu_family: u8 = 0
cpu_model: u8 = 0
cpu_stepping: u8 = 0
apic_id: u8 = 0


// Initialize CPU
init :: proc() {
    // Detect CPU vendor
    cpu_vendor = get_vendor_string()
    
    // Detect CPU brand
    cpu_brand = get_brand_string()
    
    // Detect features
    cpu_features = detect_features()
    
    // Get family/model/stepping
    eax, _, _, _ := intrinsics.cpuid(1, 0)
    cpu_family = u8((eax >> 8) & 0xF)
    cpu_model = u8((eax >> 4) & 0xF)
    cpu_stepping = u8(eax & 0xF)
    
    // Get APIC ID
    _, ebx, _, _ := intrinsics.cpuid(1, 0)
    apic_id = u8((ebx >> 24) & 0xFF)
    
    cpu_initialized = true
    
    log.info("CPU: %s", cpu_brand)
    log.info("CPU: Family %d, Model %d, Stepping %d", cpu_family, cpu_model, cpu_stepping)
}


// Get Vendor String
get_vendor_string :: proc() -> string {
    eax, ebx, ecx, edx := intrinsics.cpuid(0, 0)
    
    vendor := make([]u8, 12)
    vendor[0..3] = string(ebx)[:3]
    vendor[4..7] = string(edx)[:3]
    vendor[8..11] = string(ecx)[:3]
    
    return string(vendor)
}


// Get Brand String
get_brand_string :: proc() -> string {
    brand := make([]u8, 48)
    
    for i in 0..<3 {
        eax, ebx, ecx, edx := intrinsics.cpuid(0x80000002 + i, 0)
        
        brand[i*16..i*16+4] = string(eax)[:4]
        brand[i*16+4..i*16+8] = string(ebx)[:4]
        brand[i*16+8..i*16+12] = string(ecx)[:4]
        brand[i*16+12..i*16+16] = string(edx)[:4]
    }
    
    return string(brand)
}


// Detect CPU Features
detect_features :: proc() -> u64 {
    _, _, ecx, edx := intrinsics.cpuid(1, 0)
    
    features := u64(0)
    
    // EDX features
    if (edx & (1 << 0)) != 0 { features |= (1 << CPU_FEATURES.FPU) }
    if (edx & (1 << 9)) != 0 { features |= (1 << CPU_FEATURES.APIC) }
    if (edx & (1 << 23)) != 0 { features |= (1 << CPU_FEATURES.MMX) }
    if (edx & (1 << 25)) != 0 { features |= (1 << CPU_FEATURES.SSE) }
    if (edx & (1 << 26)) != 0 { features |= (1 << CPU_FEATURES.SSE2) }
    
    // ECX features
    if (ecx & (1 << 0)) != 0 { features |= (1 << CPU_FEATURES.SSE3) }
    if (ecx & (1 << 9)) != 0 { features |= (1 << CPU_FEATURES.SSSE3) }
    if (ecx & (1 << 19)) != 0 { features |= (1 << CPU_FEATURES.SSE4_1) }
    if (ecx & (1 << 20)) != 0 { features |= (1 << CPU_FEATURES.SSE4_2) }
    if (ecx & (1 << 27)) != 0 { features |= (1 << CPU_FEATURES.SMEP) }
    if (ecx & (1 << 28)) != 0 { features |= (1 << CPU_FEATURES.AVX) }
    
    return features
}


// Check Feature
has_feature :: proc(feature: CPU_FEATURES) -> bool {
    return (cpu_features & (1 << feature)) != 0
}


// Enable Interrupts
enable_interrupts :: proc() {
    intrinsics.sti()
}


// Disable Interrupts
disable_interrupts :: proc() {
    intrinsics.cli()
}


// Are Interrupts Enabled
interrupts_enabled :: proc() -> bool {
    rflags := intrinsics.read_rflags()
    return (rflags & (1 << 9)) != 0
}


// Halt CPU
halt :: proc() {
    intrinsics.hlt()
}


// Pause CPU (spin-wait hint)
pause :: proc() {
    intrinsics.pause()
}


// Read CR0
read_cr0 :: proc() -> u64 {
    return intrinsics.read_cr0()
}


// Write CR0
write_cr0 :: proc(value: u64) {
    intrinsics.write_cr0(value)
}


// Read CR2
read_cr2 :: proc() -> u64 {
    return intrinsics.read_cr2()
}


// Read CR3
read_cr3 :: proc() -> u64 {
    return intrinsics.read_cr3()
}


// Write CR3
write_cr3 :: proc(value: u64) {
    intrinsics.write_cr3(value)
}


// Read CR4
read_cr4 :: proc() -> u64 {
    return intrinsics.read_cr4()
}


// Write CR4
write_cr4 :: proc(value: u64) {
    intrinsics.write_cr4(value)
}


// Read EFER (Extended Feature Enable Register)
read_efer :: proc() -> u64 {
    return intrinsics.read_msr(0xC0000080)
}


// Write EFER
write_efer :: proc(value: u64) {
    intrinsics.write_msr(0xC0000080, value)
}


// Read TSC (Time Stamp Counter)
read_tsc :: proc() -> u64 {
    return intrinsics.read_tsc()
}


// Get CPU Model Name
get_model_name :: proc() -> string {
    return cpu_brand
}


// Get Features String
get_features_string :: proc() -> string {
    features := ""
    
    if has_feature(.FPU) { features += "FPU " }
    if has_feature(.APIC) { features += "APIC " }
    if has_feature(.SSE) { features += "SSE " }
    if has_feature(.SSE2) { features += "SSE2 " }
    if has_feature(.SSE3) { features += "SSE3 " }
    if has_feature(.SSSE3) { features += "SSSE3 " }
    if has_feature(.SSE4_1) { features += "SSE4.1 " }
    if has_feature(.SSE4_2) { features += "SSE4.2 " }
    if has_feature(.AVX) { features += "AVX " }
    if has_feature(.AVX2) { features += "AVX2 " }
    if has_feature(.SMEP) { features += "SMEP " }
    if has_feature(.SMAP) { features += "SMAP " }
    
    return features
}


// Kernel Panic
#[no_return]
panic :: proc(message: string) {
    disable_interrupts()
    
    log.error("KERNEL PANIC: %s", message)
    log.error("CPU: %s", cpu_brand)
    log.error("Halting...")
    
    for {
        halt()
    }
}


// Get APIC ID
get_apic_id :: proc() -> u8 {
    return apic_id
}


// Is Initialized
is_initialized :: proc() -> bool {
    return cpu_initialized
}
