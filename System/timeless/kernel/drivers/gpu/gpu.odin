// GPU Driver Framework
// Modular GPU driver system for multiple hardware vendors

package drivers.gpu

import (
    "core:log"
    "core:mem"
    "mm:physical"
    "mm:virtual"
)

// GPU Vendor Types
GPU_Vendor :: enum {
    Unknown,
    Intel,
    AMD,
    NVIDIA,
    Matrox,
    ASPEED,
    VirtualBox,
    QEMU,
    VMware,
}

// GPU Device Info
GPU_Device :: struct {
    vendor:     GPU_Vendor,
    vendor_id:  u16,
    device_id:  u16,
    revision:   u8,
    class:      u8,
    subclass:   u8,
    bar0:       uintptr,  // Framebuffer MMIO
    bar1:       uintptr,  // Additional MMIO
    bar2:       uintptr,  // Additional MMIO
    irq:        u8,
    pci_bus:    u8,
    pci_device: u8,
    pci_function: u8,
}

// Graphics Mode
Graphics_Mode :: struct {
    width:      u32,
    height:     u32,
    bpp:        u32,     // Bits per pixel
    pitch:      u32,     // Bytes per scanline
    format:     Pixel_Format,
    framebuffer: uintptr,
    size:       usize,
}

// Pixel Formats
Pixel_Format :: enum {
    RGB332,
    RGB565,
    RGB888,
    ARGB8888,
    XRGB8888,
    BGRA8888,
}

// GPU Driver Interface
GPU_Driver :: struct {
    name:           string,
    vendor:         GPU_Vendor,
    initialized:    bool,
    device:         GPU_Device,
    mode:           Graphics_Mode,
    
    // Driver methods (function pointers)
    init:           proc(device: *GPU_Device) -> bool,
    fini:           proc(),
    set_mode:       proc(width: u32, height: u32, bpp: u32) -> bool,
    get_framebuffer :: proc() -> uintptr,
    swap_buffers:   proc(),
    wait_vsync:     proc(),
    fill:           proc(x: u32, y: u32, w: u32, h: u32, color: u32),
    blit:           proc(src: uintptr, dst_x: u32, dst_y: u32, w: u32, h: u32),
}

// Global GPU State
gpu_initialized: bool = false
active_driver: GPU_Driver = GPU_Driver{}
gpu_device: GPU_Device
framebuffer_base: uintptr = 0
framebuffer_size: usize = 0


// Initialize GPU Subsystem
init :: proc() {
    log.info("GPU: Initializing graphics subsystem...")
    
    // Detect GPU via PCI enumeration
    if !detect_gpu() {
        log.warn("GPU: No supported GPU detected")
        return
    }
    
    log.info("GPU: Detected %s device (0x%04X:0x%04X)",
             gpu_device.vendor, gpu_device.vendor_id, gpu_device.device_id)
    
    // Load appropriate driver
    load_driver()
}


// Detect GPU via PCI
detect_gpu :: proc() -> bool {
    // Scan PCI bus for display controllers
    // Class 0x03 = Display Controller
    // Subclass 0x00 = VGA, 0x01 = XGA, 0x02 = 3D, 0x80 = Other
    
    // In real implementation, enumerate PCI config space
    // For now, simulate detection
    
    // Example: Detect Intel HD Graphics
    gpu_device = GPU_Device{
        vendor = .Intel,
        vendor_id = 0x8086,
        device_id = 0x5912,  // HD Graphics 630
        revision = 0x04,
        class = 0x03,
        subclass = 0x00,
        bar0 = 0xF0000000,  // MMIO region
        bar1 = 0xE0000000,  // Framebuffer aperture
        irq = 0,
        pci_bus = 0,
        pci_device = 2,
        pci_function = 0,
    }
    
    return true
}


// Load Appropriate Driver
load_driver :: proc() {
    switch gpu_device.vendor {
    case .Intel:
        log.info("GPU: Loading Intel graphics driver...")
        // drivers.gpu.intel.init(&gpu_device)
        
    case .AMD:
        log.info("GPU: Loading AMD graphics driver...")
        // drivers.gpu.amd.init(&gpu_device)
        
    case .NVIDIA:
        log.info("GPU: Loading NVIDIA graphics driver...")
        // Check if open source or proprietary
        // drivers.gpu.nvidia_open.init(&gpu_device)
        // OR
        // drivers.gpu.nvidia_proprietary.init(&gpu_device)
        
    case .VirtualBox:
        log.info("GPU: Loading VirtualBox SVGA driver...")
        // drivers.gpu.virtual.virtualbox.init(&gpu_device)
        
    case .QEMU:
        log.info("GPU: Loading QEMU VirtIO-GPU driver...")
        // drivers.gpu.virtual.qemu.init(&gpu_device)
        
    case:
        log.warn("GPU: No driver available for vendor %d", gpu_device.vendor)
    }
}


// Map GPU Memory Regions
map_gpu_memory :: proc(device: *GPU_Device) -> bool {
    // Map BAR0 (MMIO registers)
    if device.bar0 != 0 {
        // Map 1MB of MMIO space
        mmio_virt := virtual.allocate_kernel_virtual(1024 * 1024)
        if mmio_virt == 0 {
            return false
        }
        
        // Create mapping (in real implementation, modify page tables)
        // virtual.map_physical(mmio_virt, device.bar0, 1024*1024, .UNCACHED)
        
        log.info("GPU: MMIO mapped at 0x%p (physical 0x%p)", mmio_virt, device.bar0)
    }
    
    // Map framebuffer
    if device.bar1 != 0 {
        // Map framebuffer (size detected from hardware)
        fb_size := 16 * 1024 * 1024  // 16MB default
        fb_virt := virtual.allocate_kernel_virtual(fb_size)
        if fb_virt == 0 {
            return false
        }
        
        framebuffer_base = fb_virt
        framebuffer_size = fb_size
        
        log.info("GPU: Framebuffer mapped at 0x%p (physical 0x%p, %d MB)",
                 fb_virt, device.bar1, fb_size / (1024 * 1024))
    }
    
    return true
}


// Set Graphics Mode
set_mode :: proc(width: u32, height: u32, bpp: u32) -> bool {
    if !gpu_initialized {
        return false
    }
    
    if active_driver.set_mode != nil {
        return active_driver.set_mode(width, height, bpp)
    }
    
    return false
}


// Get Framebuffer Address
get_framebuffer :: proc() -> uintptr {
    return framebuffer_base
}


// Fill Rectangle
fill_rect :: proc(x: u32, y: u32, w: u32, h: u32, color: u32) {
    if !gpu_initialized {
        return
    }
    
    if active_driver.fill != nil {
        active_driver.fill(x, y, w, h, color)
    }
}


// Swap Buffers (for double buffering)
swap_buffers :: proc() {
    if !gpu_initialized {
        return
    }
    
    if active_driver.swap_buffers != nil {
        active_driver.swap_buffers()
    }
}


// Wait for Vertical Sync
wait_vsync :: proc() {
    if !gpu_initialized {
        return
    }
    
    if active_driver.wait_vsync != nil {
        active_driver.wait_vsync()
    }
}


// Check if GPU is Initialized
is_initialized :: proc() -> bool {
    return gpu_initialized
}


// Get Active Driver
get_driver :: proc() -> *GPU_Driver {
    return &active_driver
}


// Get Device Info
get_device :: proc() -> *GPU_Device {
    return &gpu_device
}
