// AMDGPU Driver - System DMA Engine
// SDMA for memory copies, fills, and GPU operations

package drivers.gpu.amd

import (
    "core:log"
    "core:mem"
    "mm:physical"
    "mm:virtual"
)

// SDMA Engine Registers
SDMA0_REGISTER_BASE :: 0x3C0000
SDMA1_REGISTER_BASE :: 0x3E0000

// SDMA Ring Buffer
SDMA_RB_SIZE :: 4096  // 4K entries (16KB)
SDMA_RB_MASK :: SDMA_RB_SIZE - 1

// SDMA Packet Opcodes
SDMA_PKT_NOP ::           0x00000000
SDMA_PKT_HEADER ::        0x00000001
SDMA_PKT_SRBM_WRITE ::    0x00000002
SDMA_PKT_REGREG ::        0x00000003
SDMA_PKT_MEMORY ::        0x00000004
SDMA_PKT_FENCE ::         0x00000005
SDMA_PKT_TRAP ::          0x00000006
SDMA_PKT_SEMAPHORE ::     0x00000007
SDMA_PKT_POLL_REG ::      0x00000008
SDMA_PKT_POLL_MEM ::      0x00000009

// Memory Copy Packet
SDMA_OP_COPY ::           0x00
SDMA_SUBOP_COPY_LINEAR :: 0x01

// Fill Packet
SDMA_OP_FILL ::           0x01

// SDMA Engine State
sdma_engine :: struct {
    engine_id: u32,
    enabled: bool,
    rb_base: u64,
    rb_size: u32,
    rb_rptr: u32,
    rb_wptr: u32,
    doorbell: u32,
}

sdma0: sdma_engine
sdma1: sdma_engine
sdma_initialized: bool = false


// Initialize SDMA Engines
init_sdma :: proc() -> bool {
    log.info("AMDGPU: Initializing SDMA engines...")
    
    // Initialize SDMA0 (main engine)
    if !init_sdma_engine(0, &sdma0) {
        log.error("AMDGPU: Failed to initialize SDMA0")
        return false
    }
    
    // Initialize SDMA1 (if available)
    // Some GPUs have dual SDMA engines
    if has_sdma1() {
        if !init_sdma_engine(1, &sdma1) {
            log.warn("AMDGPU: SDMA1 failed to initialize")
        }
    }
    
    sdma_initialized = true
    log.info("AMDGPU: SDMA engines initialized")
    
    return true
}


// Check if SDMA1 is Available
has_sdma1 :: proc() -> bool {
    // Check GPU capabilities
    // High-end GPUs have dual SDMA
    return amd_device.revision >= 0x10  // Simplified
}


// Initialize SDMA Engine
init_sdma_engine :: proc(engine_id: u32, engine: *sdma_engine) -> bool {
    log.info("AMDGPU: Initializing SDMA%d...", engine_id)
    
    engine.engine_id = engine_id
    engine.enabled = false
    
    // Get register base
    reg_base := SDMA0_REGISTER_BASE
    if engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    // Reset SDMA engine
    if !reset_sdma_engine(engine_id) {
        return false
    }
    
    // Allocate ring buffer
    if !allocate_sdma_rb(engine) {
        return false
    }
    
    // Configure ring buffer
    configure_sdma_rb(engine_id, engine)
    
    // Enable SDMA engine
    enable_sdma_engine(engine_id)
    
    // Enable doorbell
    enable_sdma_doorbell(engine_id, engine)
    
    engine.enabled = true
    log.info("AMDGPU: SDMA%d enabled (RB: %d entries)", engine_id, engine.rb_size)
    
    return true
}


// Reset SDMA Engine
reset_sdma_engine :: proc(engine_id: u32) -> bool {
    reg_base := SDMA0_REGISTER_BASE
    if engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    SDMA_RESET :: reg_base + 0x00
    
    // Assert reset
    mmio_write(SDMA_RESET, 1)
    
    // Wait for reset
    timeout := 1000
    for timeout > 0 {
        status := mmio_read(SDMA_RESET)
        if (status & 1) == 0 {
            break
        }
        timeout--
    }
    
    if timeout == 0 {
        log.error("AMDGPU: SDMA%d reset timeout", engine_id)
        return false
    }
    
    // Deassert reset
    mmio_write(SDMA_RESET, 0)
    
    return true
}


// Allocate SDMA Ring Buffer
allocate_sdma_rb :: proc(engine: *sdma_engine) -> bool {
    rb_size_bytes := SDMA_RB_SIZE * 4  // 4 bytes per entry
    
    // Allocate contiguous physical memory
    rb_phys := physical.allocate_contiguous(rb_size_bytes)
    if rb_phys == 0 {
        log.error("AMDGPU: Failed to allocate SDMA ring buffer")
        return false
    }
    
    // Map ring buffer
    rb_virt := virtual.physical_to_virtual(rb_phys)
    
    // Clear ring buffer
    mem.zero(cast([]u8)(rb_virt, rb_size_bytes))
    
    engine.rb_base = rb_phys
    engine.rb_size = SDMA_RB_SIZE
    engine.rb_rptr = 0
    engine.rb_wptr = 0
    
    log.info("AMDGPU: SDMA RB allocated at 0x%p (%d KB)", 
             rb_phys, rb_size_bytes / 1024)
    
    return true
}


// Configure SDMA Ring Buffer
configure_sdma_rb :: proc(engine_id: u32, engine: *sdma_engine) {
    reg_base := SDMA0_REGISTER_BASE
    if engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    SDMA_RB_BASE :: reg_base + 0x10
    SDMA_RB_CNTL :: reg_base + 0x14
    SDMA_RB_RPTR :: reg_base + 0x18
    SDMA_RB_WPTR :: reg_base + 0x1C
    
    // Set ring buffer base (64-bit address)
    mmio_write(SDMA_RB_BASE, u32(engine.rb_base))
    mmio_write(SDMA_RB_BASE + 4, u32(engine.rb_base >> 32))
    
    // Set ring buffer control
    rb_size_log2 := 12  // 4096 entries = 2^12
    mmio_write(SDMA_RB_CNTL, (rb_size_log2 << 0) | (1 << 8))  // Enable
    
    // Reset read/write pointers
    mmio_write(SDMA_RB_RPTR, 0)
    mmio_write(SDMA_RB_WPTR, 0)
}


// Enable SDMA Engine
enable_sdma_engine :: proc(engine_id: u32) {
    reg_base := SDMA0_REGISTER_BASE
    if engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    SDMA_ENABLE :: reg_base + 0x04
    
    // Enable SDMA
    mmio_write(SDMA_ENABLE, (1 << 0) | (1 << 1))  // Enable and clock
}


// Enable SDMA Doorbell
enable_sdma_doorbell :: proc(engine_id: u32, engine: *sdma_engine) {
    // Doorbell is used to notify SDMA of new work
    // Each engine gets a doorbell offset
    
    DOORBELL_BASE :: 0x10000  // Doorbell aperture
    DOORBELL_SIZE :: 8  // 8 bytes per doorbell
    
    doorbell_offset := DOORBELL_BASE + (engine_id * DOORBELL_SIZE)
    engine.doorbell = doorbell_offset
    
    reg_base := SDMA0_REGISTER_BASE
    if engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    SDMA_DOORBELL :: reg_base + 0x20
    
    // Configure doorbell
    mmio_write(SDMA_DOORBELL, doorbell_offset)
}


// Write SDMA Packet
sdma_write_packet :: proc(engine: *sdma_engine, packet: u32) {
    if !engine.enabled {
        return
    }
    
    // Get ring buffer address
    rb_virt := virtual.physical_to_virtual(engine.rb_base)
    
    // Write packet to ring buffer
    offset := engine.rb_wptr & SDMA_RB_MASK
    ptr := cast(*volatile u32)(rb_virt + (offset * 4))
    ptr[] = packet
    
    // Increment write pointer
    engine.rb_wptr++
    engine.rb_wptr &= SDMA_RB_MASK * 4  // Wrap at buffer size
}


// Ring Doorbell
sdma_ring_doorbell :: proc(engine: *sdma_engine) {
    if !engine.enabled {
        return
    }
    
    // Write to doorbell to notify SDMA
    doorbell_virt := virtual.physical_to_virtual(0xF0000000 + engine.doorbell)
    ptr := cast(*volatile u32)(doorbell_virt)
    ptr[] = engine.rb_wptr
}


// SDMA Memory Copy
sdma_copy :: proc(dst: u64, src: u64, size: u32) {
    if !sdma_initialized {
        log.error("AMDGPU: SDMA not initialized")
        return
    }
    
    // Build SDMA copy packet
    // Header: opcode + subopcode + size
    header := SDMA_PKT_HEADER | ((SDMA_OP_COPY << 28) | (SDMA_SUBOP_COPY_LINEAR << 20))
    
    // Count (size in DWORDs - 1)
    count := (size + 3) / 4
    sdma_write_packet(&sdma0, header | (count - 1))
    
    // Source address (64-bit)
    sdma_write_packet(&sdma0, u32(src))
    sdma_write_packet(&sdma0, u32(src >> 32))
    
    // Destination address (64-bit)
    sdma_write_packet(&sdma0, u32(dst))
    sdma_write_packet(&sdma0, u32(dst >> 32))
    
    // Ring doorbell
    sdma_ring_doorbell(&sdma0)
}


// SDMA Fill
sdma_fill :: proc(dst: u64, value: u32, size: u32) {
    if !sdma_initialized {
        return
    }
    
    // Build SDMA fill packet
    header := SDMA_PKT_HEADER | ((SDMA_OP_FILL << 28))
    
    // Count (size in DWORDs - 1)
    count := (size + 3) / 4
    sdma_write_packet(&sdma0, header | (count - 1))
    
    // Fill value
    sdma_write_packet(&sdma0, value)
    
    // Destination address (64-bit)
    sdma_write_packet(&sdma0, u32(dst))
    sdma_write_packet(&sdma0, u32(dst >> 32))
    
    // Ring doorbell
    sdma_ring_doorbell(&sdma0)
}


// SDMA Fence
sdma_fence :: proc(fence_addr: u64, fence_value: u32) {
    if !sdma_initialized {
        return
    }
    
    // Build SDMA fence packet
    header := SDMA_PKT_HEADER | ((SDMA_PKT_FENCE << 28))
    sdma_write_packet(&sdma0, header)
    
    // Fence address
    sdma_write_packet(&sdma0, u32(fence_addr))
    sdma_write_packet(&sdma0, u32(fence_addr >> 32))
    
    // Fence value
    sdma_write_packet(&sdma0, fence_value)
    
    // Ring doorbell
    sdma_ring_doorbell(&sdma0)
}


// Wait for SDMA Idle
sdma_wait_idle :: proc(engine_id: u32) -> bool {
    reg_base := SDMA0_REGISTER_BASE
    if engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    SDMA_STATUS :: reg_base + 0x40
    
    timeout := 1000000
    for timeout > 0 {
        status := mmio_read(SDMA_STATUS)
        if (status & (1 << 0)) != 0 {  // Idle bit
            return true
        }
        timeout--
    }
    
    log.error("AMDGPU: SDMA%d idle timeout", engine_id)
    return false
}


// Get SDMA Read Pointer
sdma_get_rptr :: proc(engine: *sdma_engine) -> u32 {
    if !engine.enabled {
        return 0
    }
    
    reg_base := SDMA0_REGISTER_BASE
    if engine.engine_id == 1 {
        reg_base = SDMA1_REGISTER_BASE
    }
    
    SDMA_RB_RPTR :: reg_base + 0x18
    engine.rb_rptr = mmio_read(SDMA_RB_RPTR)
    
    return engine.rb_rptr
}


// SDMA Accelerated Operations
sdma_accel_copy :: proc(dst_virt: uintptr, src_virt: uintptr, size: usize) {
    // Get physical addresses
    dst_phys := virtual.virtual_to_physical(dst_virt)
    src_phys := virtual.virtual_to_physical(src_virt)
    
    // Issue SDMA copy
    sdma_copy(dst_phys, src_phys, u32(size))
}


sdma_accel_fill :: proc(dst_virt: uintptr, value: u32, size: usize) {
    // Get physical address
    dst_phys := virtual.virtual_to_physical(dst_virt)
    
    // Issue SDMA fill
    sdma_fill(dst_phys, value, u32(size))
}
