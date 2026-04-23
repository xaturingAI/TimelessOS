// Physical Memory Manager
// Manages physical frame allocation using UEFI memory map

package mm.physical

import (
    "core:mem"
    "core:log"
    "core:math"
    "arch:x86_64/cpu"
)

// Constants
PAGE_SIZE :: 4096
FRAME_SIZE :: PAGE_SIZE
FRAMES_PER_BITMAP_BYTE :: 8


// Physical Frame Allocator State
Frame_Allocator :: struct {
    total_frames:      usize,
    free_frames:       usize,
    used_frames:       usize,
    reserved_frames:   usize,
    bitmap:            []u8,        // Bitmask of allocated frames
    bitmap_size:       usize,
    base_address:      uintptr,     // Start of usable memory
    last_allocated:    usize,       // Last allocated frame (for optimization)
}


// Memory Region Types (from UEFI)
Memory_Type :: enum {
    Reserved,
    Loader_Code,
    Loader_Data,
    Boot_Service_Code,
    Boot_Service_Data,
    Runtime_Service_Code,
    Runtime_Service_Data,
    Conventional,      // Usable RAM
    Unusable,
    ACPI_Reclaimable,
    ACPI_NVS,
    Memory_Mapped_IO,
    Memory_Mapped_IO_Port_Space,
    Pal_Code,
    Persistent,
}


// Memory Descriptor (UEFI format)
Memory_Descriptor :: struct {
    type:          Memory_Type,
    physical_start: uintptr,
    virtual_start:  uintptr,
    page_count:     u64,
    attribute:      u64,
}


// Global frame allocator
allocator: Frame_Allocator
memory_map: []Memory_Descriptor
total_physical_memory: u64


// Initialize Physical Memory Manager
init :: proc(system_table: rawptr) {
    log.info("Physical Memory: Initializing...")
    
    // Parse UEFI memory map
    parse_uefi_memory_map(system_table)
    
    // Find largest contiguous RAM region for frame allocator
    ram_region := find_largest_ram_region()
    
    if ram_region.page_count == 0 {
        log.error("Physical Memory: No usable RAM found!")
        cpu.panic("No usable physical memory")
    }
    
    log.info("Physical Memory: Largest RAM region: 0x%p - 0x%p (%d MB)",
             ram_region.physical_start,
             ram_region.physical_start + ram_region.page_count * PAGE_SIZE,
             ram_region.page_count * PAGE_SIZE / (1024 * 1024))
    
    // Initialize frame allocator bitmap
    init_frame_allocator(ram_region)
    
    // Reserve critical regions
    reserve_kernel_regions()
    
    log.info("Physical Memory: Initialized (%d frames, %d MB)",
             allocator.total_frames,
             allocator.total_frames * FRAME_SIZE / (1024 * 1024))
}


// Parse UEFI Memory Map
parse_uefi_memory_map :: proc(system_table: rawptr) {
    // Extract memory map from UEFI system table
    // In real implementation, this calls GetMemoryMap via EFI_BOOT_SERVICES
    
    // For now, create a basic memory map
    // Real implementation parses EFI_MEMORY_DESCRIPTOR array
    
    memory_map = make([]Memory_Descriptor, 32)
    
    // Typical UEFI memory map:
    // - 0x00000000 - 0x0009FFFF: Conventional (640KB)
    // - 0x000A0000 - 0x000FFFFF: Reserved (VGA, BIOS)
    // - 0x00100000 - 0x7FFFFFFF: Conventional (2GB+)
    // - 0x80000000+: Device MMIO, ACPI, etc.
    
    memory_map[0] = Memory_Descriptor{
        type = .Conventional,
        physical_start = 0x1000,
        page_count = 256,  // 1MB
    }
    
    memory_map[1] = Memory_Descriptor{
        type = .Reserved,
        physical_start = 0x101000,
        page_count = 256,
    }
    
    memory_map[2] = Memory_Descriptor{
        type = .Conventional,
        physical_start = 0x200000,
        page_count = 524288,  // 2GB
    }
}


// Find Largest Contiguous RAM Region
find_largest_ram_region :: proc() -> Memory_Descriptor {
    largest: Memory_Descriptor
    largest.page_count = 0
    
    for i in 0..<len(memory_map) {
        region := memory_map[i]
        if region.type == .Conventional {
            if region.page_count > largest.page_count {
                largest = region
            }
        }
    }
    
    return largest
}


// Initialize Frame Allocator
init_frame_allocator :: proc(ram_region: Memory_Descriptor) {
    allocator.base_address = ram_region.physical_start
    allocator.total_frames = ram_region.page_count
    allocator.free_frames = allocator.total_frames
    allocator.used_frames = 0
    allocator.reserved_frames = 0
    
    // Calculate bitmap size (1 bit per frame)
    bitmap_bytes := (allocator.total_frames + 7) / 8
    allocator.bitmap_size = bitmap_bytes
    
    // Allocate bitmap from early memory
    // In real implementation, this uses early boot allocation
    allocator.bitmap = make([]u8, bitmap_bytes)
    
    // Clear bitmap (all frames free)
    mem.zero(mem.ptr(&allocator.bitmap[0]), bitmap_bytes)
    
    allocator.last_allocated = 0
}


// Reserve Kernel Regions
reserve_kernel_regions :: proc() {
    // Reserve memory for:
    // - Kernel image
    // - Frame allocator bitmap
    // - Early page tables
    // - Reserved UEFI regions
    
    // Reserve first 1MB (BIOS, VGA, etc.)
    reserve_frames(0, 256)
    
    // Reserve kernel image region (example: 2MB at 1MB)
    reserve_frames(256, 512)
}


// Reserve a Range of Frames
reserve_frames :: proc(start_frame: usize, count: usize) {
    for i in 0..<count {
        frame := start_frame + i
        if frame < allocator.total_frames {
            set_frame_used(frame)
            allocator.reserved_frames += 1
            allocator.free_frames -= 1
        }
    }
}


// Allocate a Physical Frame
allocate_frame :: proc() -> uintptr {
    if allocator.free_frames == 0 {
        return 0  // Out of memory
    }
    
    // Find next free frame (simple linear search from last position)
    frame := find_free_frame(allocator.last_allocated)
    
    if frame == allocator.total_frames {
        // Wrap around and search from beginning
        frame = find_free_frame(0)
    }
    
    if frame >= allocator.total_frames {
        return 0  // No free frames
    }
    
    set_frame_used(frame)
    allocator.free_frames -= 1
    allocator.used_frames += 1
    allocator.last_allocated = frame + 1
    
    return allocator.base_address + frame * FRAME_SIZE
}


// Allocate Multiple Physical Frames
allocate_frames :: proc(count: usize) -> uintptr {
    if allocator.free_frames < count {
        return 0  // Out of memory
    }
    
    // Find contiguous range
    frame := find_free_frames_contiguous(count, allocator.last_allocated)
    
    if frame == allocator.total_frames {
        frame = find_free_frames_contiguous(count, 0)
    }
    
    if frame >= allocator.total_frames {
        return 0
    }
    
    // Mark all frames as used
    for i in 0..<count {
        set_frame_used(frame + i)
    }
    
    allocator.free_frames -= count
    allocator.used_frames += count
    allocator.last_allocated = frame + count
    
    return allocator.base_address + frame * FRAME_SIZE
}


// Free a Physical Frame
free_frame :: proc(address: uintptr) {
    frame := (address - allocator.base_address) / FRAME_SIZE
    
    if frame >= allocator.total_frames {
        return  // Invalid address
    }
    
    if !is_frame_used(frame) {
        return  // Already free
    }
    
    set_frame_free(frame)
    allocator.free_frames += 1
    allocator.used_frames -= 1
}


// Free Multiple Physical Frames
free_frames :: proc(address: uintptr, count: usize) {
    frame := (address - allocator.base_address) / FRAME_SIZE
    
    for i in 0..<count {
        free_frame(allocator.base_address + (frame + i) * FRAME_SIZE)
    }
}


// Find Next Free Frame
find_free_frame :: proc(start: usize) -> usize {
    for i in start..<allocator.total_frames {
        if !is_frame_used(i) {
            return i
        }
    }
    return allocator.total_frames  // Not found
}


// Find Contiguous Free Frames
find_free_frames_contiguous :: proc(count: usize, start: usize) -> usize {
    consecutive := 0
    start_frame := usize(0)
    
    for i in start..<allocator.total_frames {
        if !is_frame_used(i) {
            if consecutive == 0 {
                start_frame = i
            }
            consecutive += 1
            if consecutive == count {
                return start_frame
            }
        } else {
            consecutive = 0
        }
    }
    
    return allocator.total_frames  // Not found
}


// Check if Frame is Used
is_frame_used :: proc(frame: usize) -> bool {
    byte_index := frame / 8
    bit_index := frame % 8
    
    if byte_index >= allocator.bitmap_size {
        return true  // Out of bounds = used
    }
    
    return (allocator.bitmap[byte_index] & (1 << bit_index)) != 0
}


// Set Frame as Used
set_frame_used :: proc(frame: usize) {
    byte_index := frame / 8
    bit_index := frame % 8
    
    if byte_index < allocator.bitmap_size {
        allocator.bitmap[byte_index] |= (1 << bit_index)
    }
}


// Set Frame as Free
set_frame_free :: proc(frame: usize) {
    byte_index := frame / 8
    bit_index := frame % 8
    
    if byte_index < allocator.bitmap_size {
        allocator.bitmap[byte_index] &= ~(1 << bit_index)
    }
}


// Get Available Memory
get_available_memory :: proc() -> u64 {
    return allocator.free_frames * FRAME_SIZE
}


// Get Total Memory
get_total_memory :: proc() -> u64 {
    return allocator.total_frames * FRAME_SIZE
}


// Get Used Memory
get_used_memory :: proc() -> u64 {
    return allocator.used_frames * FRAME_SIZE
}


// Get Memory Statistics
get_stats :: proc() -> (total: u64, free: u64, used: u64, reserved: u64) {
    return allocator.total_frames * FRAME_SIZE,
           allocator.free_frames * FRAME_SIZE,
           allocator.used_frames * FRAME_SIZE,
           allocator.reserved_frames * FRAME_SIZE
}
