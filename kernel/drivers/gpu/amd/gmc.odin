// AMDGPU Driver - Graphics Memory Controller
// VRAM management, GART, and memory controller initialization

package drivers.gpu.amd

import (
    "core:log"
    "core:mem"
    "mm:physical"
    "mm:virtual"
)

// GMC (Graphics Memory Controller) Registers
MC_VM_FB_LOCATION_BASE ::    0x00F5
MC_VM_FB_LOCATION_TOP ::     0x00F6
MC_VM_SYSTEM_APERTURE_LOW :: 0x00F7
MC_VM_SYSTEM_APERTURE_HIGH :: 0x00F8
MC_VM_AGP_TOP ::             0x00F9
MC_VM_AGP_BOT ::             0x00FA
MC_VM_AGP_BASE ::            0x00FB

// VRAM Configuration
VRAM_TYPE :: enum {
    Unknown,
    DDR3,
    DDR4,
    DDR5,
    DDR6,  // GDDR6
    HBM,
    HBM2,
}

// Memory Controller State
gmc_state :: struct {
    vram_size: u64,
    vram_type: VRAM_TYPE,
    vram_width: u32,  // Bus width in bits
    vram_channels: u32,
    fb_location: u64,
    fb_base: u64,
    fb_top: u64,
    gart_base: u64,
    gart_size: u64,
    aperture_base: u64,
    aperture_size: u64,
}

gmc: gmc_state


// Initialize Graphics Memory Controller
init_gmc :: proc(device_id: u16) -> bool {
    log.info("AMDGPU: Initializing Graphics Memory Controller...")
    
    // Detect VRAM type and size
    if !detect_vram_config() {
        log.error("AMDGPU: Failed to detect VRAM configuration")
        return false
    }
    
    log.info("AMDGPU: VRAM: %d MB (%s, %d-bit bus)", 
             gmc.vram_size / (1024 * 1024), 
             vram_type_string(gmc.vram_type),
             gmc.vram_width)
    
    // Set up framebuffer location
    setup_fb_location()
    
    // Configure GART (Graphics Address Remapping Table)
    if !setup_gart() {
        return false
    }
    
    // Set up system aperture
    setup_system_aperture()
    
    // Initialize VM (Virtual Memory)
    init_vm()
    
    log.info("AMDGPU: GMC initialized")
    return true
}


// Detect VRAM Configuration
detect_vram_config :: proc() -> bool {
    // Read VRAM info from registers
    CONFIG_MEMSIZE :: 0x5560
    MC_CONFIG :: 0x2004
    
    memsize := mmio_read(CONFIG_MEMSIZE)
    gmc.vram_size = u64(memsize)
    
    // Detect VRAM type from BIOS or registers
    // This is simplified - real detection reads from VBIOS
    
    // Check for HBM (High Bandwidth Memory)
    if (mmio_read(MC_CONFIG) & (1 << 20)) != 0 {
        gmc.vram_type = .HBM2
        gmc.vram_width = 4096  // 4096-bit for HBM2
    } else {
        // Assume GDDR6 for modern cards
        gmc.vram_type = .DDR6
        gmc.vram_width = 256  // Typical 256-bit bus
    }
    
    // Calculate channels based on width
    gmc.vram_channels = gmc.vram_width / 64
    
    return true
}


// VRAM Type String
vram_type_string :: proc(t: VRAM_TYPE) -> string {
    switch t {
    case .DDR3: return "DDR3"
    case .DDR4: return "DDR4"
    case .DDR5: return "DDR5"
    case .DDR6: return "GDDR6"
    case .HBM: return "HBM"
    case .HBM2: return "HBM2"
    case: return "Unknown"
    }
}


// Set Up Framebuffer Location
setup_fb_location :: proc() {
    // FB location: base and top addresses
    // FB is typically at 0x80000000 for 2GB VRAM
    
    fb_size_mb := gmc.vram_size / (1024 * 1024)
    
    // FB base at 0
    gmc.fb_base = 0
    
    // FB top at VRAM size - 1
    gmc.fb_top = (fb_size_mb - 1) << 20  // Convert to 1MB units
    
    // Program FB location registers
    mmio_write(MC_VM_FB_LOCATION_BASE, u32(gmc.fb_base >> 24))
    mmio_write(MC_VM_FB_LOCATION_TOP, u32(gmc.fb_top >> 24))
    
    log.info("AMDGPU: FB location: 0x%p - 0x%p", gmc.fb_base, gmc.fb_top)
}


// Set Up GART (Graphics Address Remapping Table)
setup_gart :: proc() -> bool {
    GART_SIZE :: 256 * 1024 * 1024  // 256MB GART
    
    gmc.gart_size = GART_SIZE
    gmc.gart_base = gmc.fb_top + 1  // After framebuffer
    
    // Allocate GART table in VRAM
    gart_table_size := 4096  // 4KB page table
    gart_table_phys := physical.allocate_contiguous(gart_table_size)
    
    if gart_table_phys == 0 {
        log.error("AMDGPU: Failed to allocate GART table")
        return false
    }
    
    gart_table_virt := virtual.physical_to_virtual(gart_table_phys)
    
    // Clear GART table
    mem.zero(cast([]u8)(gart_table_virt, gart_table_size))
    
    // Program GART registers
    MC_VM_AGP_BASE := 0x00FB
    MC_VM_AGP_BOT := 0x00FA
    MC_VM_AGP_TOP := 0x00F9
    
    mmio_write(MC_VM_AGP_BASE, u32(gmc.gart_base >> 24))
    mmio_write(MC_VM_AGP_BOT, 0)
    mmio_write(MC_VM_AGP_TOP, u32((gmc.gart_base + GART_SIZE - 1) >> 24))
    
    log.info("AMDGPU: GART: %d MB at 0x%p", GART_SIZE / (1024 * 1024), gmc.gart_base)
    
    return true
}


// Set Up System Aperture
setup_system_aperture :: proc() {
    // System aperture for CPU access to VRAM
    // Typically at 0x00000000FFFFFFFF for 4GB
    
    SYSTEM_APERTURE_SIZE :: 4 * 1024 * 1024 * 1024  // 4GB
    
    gmc.aperture_base = 0
    gmc.aperture_size = SYSTEM_APERTURE_SIZE
    
    MC_VM_SYSTEM_APERTURE_LOW := 0x00F7
    MC_VM_SYSTEM_APERTURE_HIGH := 0x00F8
    
    mmio_write(MC_VM_SYSTEM_APERTURE_LOW, 0)
    mmio_write(MC_VM_SYSTEM_APERTURE_HIGH, u32(SYSTEM_APERTURE_SIZE >> 24))
}


// Initialize Virtual Memory
init_vm :: proc() {
    log.info("AMDGPU: Initializing virtual memory...")
    
    // VM is used for GPU page tables
    // Allows GPU to access system memory and VRAM with virtual addresses
    
    // Enable VM in MC
    MC_VM_CONFIG :: 0x2000
    VM_ENABLE :: (1 << 0)
    
    mmio_write(MC_VM_CONFIG, VM_ENABLE)
    
    // Set up page table base
    // This would point to the GPU page directory
}


// Allocate VRAM
allocate_vram :: proc(size: usize, align: usize) -> u64 {
    // Simple VRAM allocator (bump allocator for now)
    // Real implementation needs proper memory management
    
    static vram_offset: u64 = 0
    
    // Align allocation
    aligned_offset := (vram_offset + align - 1) & ~(align - 1)
    
    if aligned_offset + size > gmc.vram_size {
        return 0  // Out of VRAM
    }
    
    vram_offset = aligned_offset + size
    return gmc.fb_base + aligned_offset
}


// Free VRAM
free_vram :: proc(addr: u64, size: usize) {
    // Simple implementation - real needs proper tracking
}


// Map VRAM to CPU
map_vram :: proc(vram_addr: u64, size: usize) -> uintptr {
    // Map VRAM region for CPU access
    // This creates a CPU mapping of GPU memory
    
    cpu_addr := virtual.allocate_kernel_virtual(size)
    if cpu_addr == 0 {
        return 0
    }
    
    // Create mapping (uncached or write-combined)
    virtual.map_physical(cpu_addr, vram_addr, size, .WRITE_COMBINED)
    
    return cpu_addr
}


// GART Mapping
gart_map :: proc(phys: u64, size: usize) -> u64 {
    // Map physical memory through GART for GPU access
    // Allows GPU to access system memory
    
    // Allocate GART entry
    gart_entry := allocate_gart_entry(size)
    if gart_entry == 0 {
        return 0
    }
    
    // Program GART PTE
    program_gart_pte(gart_entry, phys, size)
    
    return gmc.gart_base + gart_entry
}


// Allocate GART Entry
allocate_gart_entry :: proc(size: usize) -> u64 {
    // Simple GART allocator
    static gart_offset: u64 = 0
    
    PAGE_SIZE :: 4096
    pages := (size + PAGE_SIZE - 1) / PAGE_SIZE
    
    entry := gart_offset
    gart_offset += pages * PAGE_SIZE
    
    if gart_offset > gmc.gart_size {
        return 0
    }
    
    return entry
}


// Program GART PTE
program_gart_pte :: proc(entry: u64, phys: u64, size: usize) {
    // Write GART page table entry
    // Format depends on GPU generation
    
    PAGE_SIZE :: 4096
    pages := (size + PAGE_SIZE - 1) / PAGE_SIZE
    
    for i in 0..<pages {
        pte_addr := gmc.gart_base + entry + (i * PAGE_SIZE)
        pte_value := phys + (i * PAGE_SIZE)
        
        // Set valid bit and other flags
        pte_value |= (1 << 0)  // Valid
        pte_value |= (1 << 1)  // Readable
        pte_value |= (1 << 2)  // Writable
        
        // Write PTE to GART table
        // This would write to the GART table in VRAM
    }
}
