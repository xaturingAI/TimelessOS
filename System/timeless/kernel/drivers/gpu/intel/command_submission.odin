// Intel Integrated Graphics Driver - Command Submission
// Ring buffers, command submission, and GPU execution

package drivers.gpu.intel

import (
    "core:log"
    "core:mem"
    "core:intrinsics"
    "mm:physical"
    "mm:virtual"
)

// Ring Buffer Constants
RING_BUFFER_SIZE :: 16 * 1024  // 16KB ring buffer
RING_BUFFER_MASK :: RING_BUFFER_SIZE - 1
BATCH_BUFFER_SIZE :: 4 * 1024  // 4KB batch buffer

// GPU Engine Types
GPU_ENGINE :: enum {
    RCS,  // Render Command Streamer
    BCS,  // Blitter Command Streamer
    VCS,  // Video Command Streamer
    VECS, // Video Enhancement Command Streamer
}

// Command Parser Opcodes (Gen8+)
MI_BATCH_BUFFER_START ::      0x31000000
MI_BATCH_BUFFER_END ::        0x05000000
MI_NOOP ::                    0x00000000
MI_STORE_DWORD_IMM ::         0x31200000
MI_LOAD_REGISTER_IMM ::       0x21000000
MI_FLUSH_DW ::                0x26000000

// 3D Pipeline Commands
3DSTATE_PIPELINE_SELECT ::    0x60000000
3DSTATE_VIEWPORT_STATE_POINTERS :: 0x781A0000
3DSTATE_CC_STATE_POINTERS ::  0x781B0000
3DSTATE_SCISSOR_STATE_POINTERS :: 0x781C0000
3DSTATE_VERTEX_BUFFERS ::     0x78080000
3DSTATE_VERTEX_ELEMENTS ::    0x78090000
3DSTATE_INDEX_BUFFER ::       0x780A0000
3DSTATE_DRAWING_RECTANGLE ::  0x78100000
3DSTATE_CONSTANT_COLOR ::     0x78010000
3DSTATE_DEPTH_BUFFER ::       0x78030000
3DSTATE_GS ::                 0x78050000
3DSTATE_CLIP ::               0x78060000
3DSTATE_SF ::                 0x78070000
3DSTATE_WM ::                 0x78080000
3DSTATE_CONSTANT_VS ::        0x78090000
3DSTATE_CONSTANT_GS ::        0x780A0000
3DSTATE_CONSTANT_PS ::        0x780B0000

// Ring Buffer State
ring_buffer: [RING_BUFFER_SIZE]u8
ring_head: u32 = 0
ring_tail: u32 = 0
ring_space: u32 = RING_BUFFER_SIZE

// GPU Engine State
engine_initialized: [4]bool  // One per engine type
current_engine: GPU_ENGINE = .RCS

// Batch Buffer
batch_buffer: [BATCH_BUFFER_SIZE]u32
batch_pos: u32 = 0
batch_active: bool = false


// Initialize Ring Buffer
init_ring_buffer :: proc() -> bool {
    log.info("Intel GPU: Initializing ring buffer...")
    
    // Allocate ring buffer in VRAM
    ring_phys := physical.allocate_contiguous(RING_BUFFER_SIZE)
    if ring_phys == 0 {
        log.error("Intel GPU: Failed to allocate ring buffer")
        return false
    }
    
    // Map ring buffer
    ring_virt := virtual.physical_to_virtual(ring_phys)
    if ring_virt == 0 {
        log.error("Intel GPU: Failed to map ring buffer")
        return false
    }
    
    mem.zero(ring_buffer[:])
    
    // Set up ring buffer control registers
    RINGBUF_CTRL :: 0x2000
    RINGBUF_HEAD :: 0x2004
    RINGBUF_TAIL :: 0x2008
    RINGBUF_START :: 0x200C
    
    // Configure ring buffer (Gen8+ format)
    ctrl_value := (RING_BUFFER_SIZE >> 12) - 1  // Size in 4KB units
    mmio_write(RINGBUF_CTRL, ctrl_value)
    mmio_write(RINGBUF_START, u32(ring_phys))
    mmio_write(RINGBUF_HEAD, 0)
    mmio_write(RINGBUF_TAIL, 0)
    
    log.info("Intel GPU: Ring buffer allocated at 0x%p (physical 0x%p)", 
             ring_virt, ring_phys)
    
    return true
}


// Get Available Space in Ring
ring_space_available :: proc() -> u32 {
    if ring_tail >= ring_head {
        return RING_BUFFER_SIZE - (ring_tail - ring_head) - 1
    }
    return ring_head - ring_tail - 1
}


// Wait for Space in Ring
ring_wait_for_space :: proc(bytes_needed: u32) -> bool {
    timeout := 1000000
    
    for ring_space_available() < bytes_needed && timeout > 0 {
        // Update head from hardware
        ring_head = mmio_read(0x2004)  // RINGBUF_HEAD
        timeout--
    }
    
    return timeout > 0
}


// Write DWORD to Ring
ring_write_dword :: proc(value: u32) {
    if !ring_wait_for_space(4) {
        log.error("Intel GPU: Ring buffer full!")
        return
    }
    
    offset := ring_tail & RING_BUFFER_MASK
    ring_buffer[offset] = cast(u8)(value)
    ring_buffer[offset+1] = cast(u8)(value >> 8)
    ring_buffer[offset+2] = cast(u8)(value >> 16)
    ring_buffer[offset+3] = cast(u8)(value >> 24)
    
    ring_tail += 4
    ring_tail &= RING_BUFFER_MASK
    
    // Update tail register
    mmio_write(0x2008, ring_tail)  // RINGBUF_TAIL
}


// Write Batch to Ring
ring_write_batch :: proc(batch_phys: u32) {
    // MI_BATCH_BUFFER_START command
    ring_write_dword(MI_BATCH_BUFFER_START | (1 << 8))  // Relocated
    ring_write_dword(batch_phys)
    ring_write_dword(0)
    
    // Flush the batch
    ring_flush()
}


// Flush Ring Buffer
ring_flush :: proc() {
    // Ensure all commands are visible to GPU
    intrinsics.memory_barrier()
    
    // Update tail register to notify GPU
    mmio_write(0x2008, ring_tail)
    
    // Ring doorbell (Gen8+)
    mmio_write(0x20A0, ring_tail)  // RING_EXE_LIST
}


// Begin Batch Buffer
batch_begin :: proc() {
    batch_pos = 0
    batch_active = true
}


// Add DWORD to Batch
batch_write_dword :: proc(value: u32) {
    if batch_pos >= BATCH_BUFFER_SIZE {
        log.error("Intel GPU: Batch buffer full!")
        return
    }
    
    batch_buffer[batch_pos] = value
    batch_pos++
}


// End Batch Buffer and Submit
batch_end :: proc() -> bool {
    if !batch_active {
        return false
    }
    
    // Add MI_BATCH_BUFFER_END
    batch_write_dword(MI_BATCH_BUFFER_END)
    
    // Allocate batch buffer in VRAM
    batch_phys := physical.allocate_contiguous(BATCH_BUFFER_SIZE)
    if batch_phys == 0 {
        log.error("Intel GPU: Failed to allocate batch buffer")
        return false
    }
    
    // Copy batch to VRAM
    batch_virt := virtual.physical_to_virtual(batch_phys)
    mem.copy(
        cast([]u8)(batch_virt, BATCH_BUFFER_SIZE),
        cast([]u8)(&batch_buffer[0], batch_pos * 4),
    )
    
    // Submit batch via ring buffer
    ring_write_batch(batch_phys)
    
    batch_active = false
    return true
}


// Wait for GPU to Finish
gpu_wait_idle :: proc() -> bool {
    timeout := 10000000
    
    for timeout > 0 {
        // Check GPU status register
        GPU_STATUS :: 0x2000
        status := mmio_read(GPU_STATUS)
        
        // Check if GPU is idle (bit 31)
        if (status & (1 << 31)) != 0 {
            return true
        }
        
        timeout--
    }
    
    log.error("Intel GPU: Timeout waiting for GPU idle")
    return false
}


// Submit 3D Rendering Commands
submit_3d_commands :: proc() {
    batch_begin()
    
    // Pipeline Select (3D mode)
    batch_write_dword(3DSTATE_PIPELINE_SELECT | (0 << 16))
    
    // State pointers
    batch_write_dword(3DSTATE_VIEWPORT_STATE_POINTERS)
    batch_write_dword(0)  // Null viewport
    
    batch_write_dword(3DSTATE_CC_STATE_POINTERS)
    batch_write_dword(0)  // Null CC state
    
    batch_write_dword(3DSTATE_SCISSOR_STATE_POINTERS)
    batch_write_dword(0)  // Null scissor
    
    // Set up drawing rectangle
    batch_write_dword(3DSTATE_DRAWING_RECTANGLE | 3)
    batch_write_dword(0)  // Min X, Y
    batch_write_dword((intel_current_mode.width << 16) | intel_current_mode.height)
    batch_write_dword(0)  // Origin
    batch_write_dword(0xFFFFFFFF)  // Clip max
    
    // Constant color (clear color)
    batch_write_dword(3DSTATE_CONSTANT_COLOR | 1)
    batch_write_dword(0xFF000000)  // Black
    
    // End batch
    batch_end()
}


// Clear Screen
clear_screen :: proc(color: u32) {
    batch_begin()
    
    // Set clear color
    batch_write_dword(3DSTATE_CONSTANT_COLOR | 1)
    batch_write_dword(color)
    
    // Clear command would go here
    // For now, use CPU fill
    fill(0, 0, intel_current_mode.width, intel_current_mode.height, color)
    
    batch_end()
}


// Initialize GPU Engines
init_engines :: proc() -> bool {
    log.info("Intel GPU: Initializing command engines...")
    
    // Initialize Render Command Streamer
    if !init_ring_buffer() {
        return false
    }
    
    engine_initialized[cast(int)(.RCS)] = true
    
    // Initialize other engines if available
    // BCS (Blitter) - for 2D operations
    // VCS (Video) - for video decode
    // VECS (Video Enhancement) - for video processing
    
    log.info("Intel GPU: RCS engine initialized")
    
    return true
}


// Execute Command List
execute_commands :: proc(commands: []u32) -> bool {
    if !engine_initialized[cast(int)(.RCS)] {
        log.error("Intel GPU: RCS not initialized")
        return false
    }
    
    batch_begin()
    
    // Copy commands to batch
    for cmd in commands {
        batch_write_dword(cmd)
    }
    
    return batch_end()
}


// GPU Memory Management
gpu_allocate :: proc(size: usize) -> uintptr {
    phys := physical.allocate_contiguous(size)
    if phys == 0 {
        return 0
    }
    return virtual.physical_to_virtual(phys)
}


gpu_free :: proc(virt: uintptr, size: usize) {
    phys := virtual.virtual_to_physical(virt)
    physical.free(phys, size)
}
