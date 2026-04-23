// Intel Integrated Graphics Driver
// Supports HD Graphics, Iris, and UHD Graphics

package drivers.gpu.intel

import (
    "core:log"
    "core:mem"
    "core:intrinsics"
    "mm:virtual"
    "drivers:gpu"
    "mm:physical"
)

// Intel GPU Register Offsets (MMIO)
// GPU State
intel_initialized: bool = false
intel_device: gpu.GPU_Device
intel_mmio_base: uintptr = 0
intel_fb_base: uintptr = 0
intel_fb_size: usize = 0
intel_current_mode: gpu.Graphics_Mode
intel_pipe: DISPLAY_PIPE = .Pipe_A
intel_connector: Connector_State


// Initialize Intel GPU
init :: proc(device: *gpu.GPU_Device) -> bool {
    log.info("Intel GPU: Initializing...")
    
    intel_device = device[]
    
    // Initialize display controller
    if !init_display_controller() {
        log.error("Intel GPU: Failed to initialize display controller")
        return false
    }
    
    // Map MMIO region
    if !map_mmio() {
        log.error("Intel GPU: Failed to map MMIO")
        return false
    }
    
    // Map framebuffer
    if !map_framebuffer() {
        log.error("Intel GPU: Failed to map framebuffer")
        return false
    }
    
    // Initialize display engine
    if !init_display_engine() {
        log.error("Intel GPU: Failed to initialize display engine")
        return false
    }
    
    // Initialize command submission
    if !init_engines() {
        log.error("Intel GPU: Failed to initialize command engines")
        return false
    }
    
    // Set default mode
    if !set_display_mode(1920, 1080, 32) {
        log.error("Intel GPU: Failed to set display mode")
        return false
    }
    
    intel_initialized = true
    log.info("Intel GPU: Initialized")
    
    return true
}


// Map MMIO Region
map_mmio :: proc() -> bool {
    if intel_device.bar0 == 0 {
        return false
    }
    
    // Map 2MB of MMIO space
    mmio_size := 2 * 1024 * 1024
    intel_mmio_base = virtual.physical_to_virtual(intel_device.bar0)
    
    // Create uncached mapping for MMIO
    virtual.map_physical(intel_mmio_base, intel_device.bar0, mmio_size, .UNCACHED)
    
    log.info("Intel GPU: MMIO mapped at 0x%p", intel_mmio_base)
    return true
}


// Map Framebuffer
map_framebuffer :: proc() -> bool {
    if intel_device.bar1 == 0 {
        return false
    }
    
    // Allocate 16MB for framebuffer
    intel_fb_size = 16 * 1024 * 1024
    
    // Allocate contiguous physical memory for framebuffer
    fb_phys := physical.allocate_contiguous(intel_fb_size)
    if fb_phys == 0 {
        log.error("Intel GPU: Failed to allocate framebuffer")
        return false
    }
    
    intel_fb_base = virtual.physical_to_virtual(fb_phys)
    
    // Create write-combined mapping for framebuffer
    virtual.map_physical(intel_fb_base, fb_phys, intel_fb_size, .WRITE_COMBINED)
    
    log.info("Intel GPU: Framebuffer mapped at 0x%p", intel_fb_base)
    return true
}


// Initialize Display Engine
init_display_engine :: proc() -> bool {
    // Enable display power well
    enable_power_well()
    
    // Configure display pipe
    if !configure_pipe_legacy() {
        return false
    }
    
    // Configure display plane
    if !configure_plane_legacy() {
        return false
    }
    
    // Enable interrupts
    enable_interrupts()
    
    return true
}


// Legacy Pipe Configuration (fallback)
configure_pipe_legacy :: proc() -> bool {
    // Simple pipe config for basic modesetting
    htotal := 2200
    hblank := 280
    vtotal := 1125
    vblank := 45
    
    mmio_write(INTELPipeA_HTOTAL, (htotal << 16) | hblank)
    mmio_write(INTELPipeA_VTOTAL, (vtotal << 16) | vblank)
    mmio_write(INTELPipeA_CONF, PIPE_ENABLE | PIPE_VSYNC_ENABLE)
    
    return true
}


// Legacy Plane Configuration (fallback)
configure_plane_legacy :: proc() -> bool {
    pitch := intel_current_mode.pitch
    mmio_write(INTEL_DSPSTRIDE, pitch)
    
    surface_addr := intel_device.bar1
    mmio_write(INTEL_DSPSURF, u32(surface_addr))
    
    mmio_write(INTEL_DSPCNTR, DISPLAY_PLANE_ENABLE)
    
    return true
}


// Enable Power Well
enable_power_well :: proc() {
    // Enable display power well for register access
    // This varies by generation (Gen8+, Gen9+, etc.)
    
    // For Gen9+ (Skylake and newer)
    POWER_WELL_CONTROL :: 0x45400
    POWER_WELL_REQUEST :: (1 << 31)
    POWER_WELL_ENABLED :: (1 << 30)
    
    // Request power well
    mmio_write(POWER_WELL_CONTROL, POWER_WELL_REQUEST)
    
    // Wait for power well to enable
    timeout := 1000
    for timeout > 0 {
        status := mmio_read(POWER_WELL_CONTROL)
        if (status & POWER_WELL_ENABLED) != 0 {
            break
        }
        timeout--
    }
}


// Enable Interrupts
enable_interrupts :: proc() {
    // Enable vertical blank interrupt
    mmio_write(INTEL_SDEIER, (1 << 0))  // VBlank Pipe A
}


// Set Graphics Mode
set_mode :: proc(width: u32, height: u32, bpp: u32) -> bool {
    log.info("Intel GPU: Setting mode %dx%d@%d", width, height, bpp)
    
    intel_current_mode = gpu.Graphics_Mode{
        width = width,
        height = height,
        bpp = bpp,
        pitch = width * (bpp / 8),
        format = .ARGB8888,
        framebuffer = intel_fb_base,
        size = intel_fb_size,
    }
    
    // Reconfigure pipe and plane for new mode
    return set_display_mode(width, height, bpp)
}


// Accelerated Fill using Blitter
fill_accel :: proc(x: u32, y: u32, w: u32, h: u32, color: u32) {
    // Use blitter command stream for fast fills
    batch_begin()
    
    // XY_SRC_COPY_BLT command
    BLT_CMD := (0x53 << 24) | (3 << 26) | (1 << 24)
    batch_write_dword(BLT_CMD | (4 << 16))  // 4 bytes per pixel
    batch_write_dword((y << 16) | x)
    batch_write_dword(((y + h) << 16) | (x + w))
    batch_write_dword(u32(intel_fb_base) + (y * intel_current_mode.pitch) + (x * 4))
    batch_write_dword(0)  // Pattern
    batch_write_dword(color)
    
    batch_end()
}


// Accelerated Blit
blit_accel :: proc(src: uintptr, dst_x: u32, dst_y: u32, w: u32, h: u32) {
    batch_begin()
    
    // SRC_COPY_BLT command
    BLT_CMD := (0x53 << 24) | (3 << 26)
    batch_write_dword(BLT_CMD | (4 << 16))
    batch_write_dword((dst_y << 16) | dst_x)
    batch_write_dword(((dst_y + h) << 16) | (dst_x + w))
    batch_write_dword(u32(intel_fb_base) + (dst_y * intel_current_mode.pitch) + (dst_x * 4))
    batch_write_dword(u32(src))
    batch_write_dword(intel_current_mode.pitch)
    
    batch_end()
}


// MMIO Read
mmio_read :: proc(offset: u32) -> u32 {
    ptr := cast(*volatile u32)(intel_mmio_base + offset)
    return ptr[]
}


// MMIO Write
mmio_write :: proc(offset: u32, value: u32) {
    ptr := cast(*volatile u32)(intel_mmio_base + offset)
    ptr[] = value
}


// Finalize Driver
fini :: proc() {
    // Disable command engines
    // gpu_wait_idle()
    
    // Disable display plane
    mmio_write(INTEL_DSPCNTR, DISPLAY_PLANE_DISABLE)
    
    // Disable pipe
    mmio_write(INTELPipeA_CONF, PIPE_DISABLE)
    
    // Disable interrupts
    mmio_write(INTEL_SDEIER, 0)
    
    intel_initialized = false
}


// Check if Initialized
is_initialized :: proc() -> bool {
    return intel_initialized
}


// Get Current Mode
get_mode :: proc() -> *gpu.Graphics_Mode {
    return &intel_current_mode
}

// Export functions for modesetting and command submission
// These are used by the integrated modules
export_ring_buffer :: proc() -> *[]u8 {
    return &ring_buffer[:]
}

export_batch_buffer :: proc() -> *[]u32 {
    return &batch_buffer[:]
}

    pitch := intel_current_mode.pitch / 4  // In pixels
    
    for row in 0..<h {
        for col in 0..<w {
            idx := (y + row) * pitch + (x + col)
            fb[idx] = color
        }
    }
}


// Blit Image
blit :: proc(src: uintptr, dst_x: u32, dst_y: u32, w: u32, h: u32) {
    // Copy from source to framebuffer
    // In real implementation, use GPU BLT engine
    
    src_data := cast(*u32)(src)
    fb := cast(*u32)(intel_fb_base)
    pitch := intel_current_mode.pitch / 4
    
    for row in 0..<h {
        for col in 0..<w {
            src_idx := row * w + col
            dst_idx := (dst_y + row) * pitch + (dst_x + col)
            fb[dst_idx] = src_data[src_idx]
        }
    }
}


// MMIO Read
mmio_read :: proc(offset: u32) -> u32 {
    ptr := cast(*volatile u32)(intel_mmio_base + offset)
    return ptr[]
}


// MMIO Write
mmio_write :: proc(offset: u32, value: u32) {
    ptr := cast(*volatile u32)(intel_mmio_base + offset)
    ptr[] = value
}


// Finalize Driver
fini :: proc() {
    // Disable display plane
    mmio_write(INTEL_DSPCNTR, DISPLAY_PLANE_DISABLE)
    
    // Disable pipe
    mmio_write(INTELPipeA_CONF, PIPE_DISABLE)
    
    // Disable interrupts
    mmio_write(INTEL_SDEIER, 0)
    
    intel_initialized = false
}


// Check if Initialized
is_initialized :: proc() -> bool {
    return intel_initialized
}


// Get Current Mode
get_mode :: proc() -> *gpu.Graphics_Mode {
    return &intel_current_mode
}
