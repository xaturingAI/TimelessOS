// Kernel Heap Manager
// Dynamic memory allocation for kernel space

package mm.heap

import (
    "core:mem"
    "core:log"
    "core:math"
    "mm:virtual"
    "mm:physical"
    "arch:x86_64/cpu"
)

// Constants
MIN_BLOCK_SIZE :: 32
HEAP_CHUNK_SIZE :: 4 * 1024 * 1024  // 4MB chunks


// Heap Block Header
Block_Header :: struct {
    size:  usize,     // Size of block (excluding header)
    flags: u32,       // Block flags
    magic: u32,       // Magic number for validation
    next:  *Block_Header,  // Next free block (when free)
    prev:  *Block_Header,  // Previous free block (when free)
}

BLOCK_MAGIC :: 0xDEADBEEF
BLOCK_FREE :: (1 << 0)
BLOCK_LARGE :: (1 << 1)


// Heap Arena
Heap_Arena :: struct {
    base:      uintptr,
    size:      usize,
    used:      usize,
    free_list: *Block_Header,
    next:      *Heap_Arena,
}


// Global heap state
heap_initialized: bool = false
main_arena: Heap_Arena
first_arena: *Heap_Arena
total_allocated: usize = 0
total_freed: usize = 0


// Initialize Kernel Heap
init :: proc() {
    log.info("Kernel Heap: Initializing...")
    
    // Allocate first arena from virtual memory manager
    arena_size := HEAP_CHUNK_SIZE
    arena_base := virtual.allocate_kernel_virtual(arena_size)
    
    if arena_base == 0 {
        cpu.panic("Kernel Heap: Failed to allocate initial arena")
    }
    
    // Set up main arena
    main_arena = Heap_Arena{
        base = arena_base,
        size = arena_size,
        used = 0,
        next = nil,
    }
    
    // Create initial free block spanning entire arena
    header_size := size_of(Block_Header)
    initial_block := cast(*Block_Header)(arena_base)
    initial_block.size = arena_size - header_size
    initial_block.flags = BLOCK_FREE
    initial_block.magic = BLOCK_MAGIC
    initial_block.next = nil
    initial_block.prev = nil
    
    main_arena.free_list = initial_block
    first_arena = &main_arena
    
    heap_initialized = true
    
    log.info("Kernel Heap: Initialized at 0x%p (%d MB)", arena_base, arena_size / (1024 * 1024))
}


// Allocate Memory
alloc :: proc(size: usize) -> rawptr {
    if !heap_initialized {
        cpu.panic("Kernel Heap: Not initialized")
    }
    
    if size == 0 {
        return nil
    }
    
    // Align size
    aligned_size := math.max(size, MIN_BLOCK_SIZE)
    aligned_size = (aligned_size + 7) & ~7  // 8-byte alignment
    
    header_size := size_of(Block_Header)
    total_size := header_size + aligned_size
    
    // Find free block (first-fit)
    block := find_free_block(total_size)
    
    if block == nil {
        // No suitable block found - expand heap
        block = expand_heap(total_size)
        if block == nil {
            return nil  // Out of memory
        }
    }
    
    // Split block if there's enough remaining space
    remaining := block.size - total_size
    if remaining >= MIN_BLOCK_SIZE + header_size {
        // Create new free block from remainder
        new_block := cast(*Block_Header)(uintptr(block) + header_size + total_size)
        new_block.size = remaining - header_size
        new_block.flags = BLOCK_FREE
        new_block.magic = BLOCK_MAGIC
        new_block.next = block.next
        new_block.prev = block.prev
        
        // Update linked list
        if block.next != nil {
            block.next.prev = new_block
        }
        block.next = new_block
        block.prev = new_block
        
        block.size = total_size - header_size
    }
    
    // Mark block as allocated
    block.flags &= ~BLOCK_FREE
    block.next = nil
    block.prev = nil
    
    total_allocated += block.size
    arena_used() += block.size + header_size
    
    // Zero out memory (security)
    data_ptr := cast(rawptr)(uintptr(block) + header_size)
    mem.zero(data_ptr, block.size)
    
    return data_ptr
}


// Allocate Aligned Memory
alloc_aligned :: proc(size: usize, alignment: usize) -> rawptr {
    // For simplicity, over-allocate and adjust
    // Real implementation would use more sophisticated alignment
    extra := alignment
    ptr := cast(uintptr)(alloc(size + extra))
    
    aligned_ptr := (ptr + alignment - 1) & ~(alignment - 1)
    offset := aligned_ptr - ptr
    
    // Store offset to recover original pointer on free
    // (In real implementation, this would be in header)
    
    return cast(rawptr)(aligned_ptr)
}


// Allocate and Zero Memory
alloc_zero :: proc(size: usize) -> rawptr {
    ptr := alloc(size)
    if ptr != nil {
        mem.zero(ptr, size)
    }
    return ptr
}


// Free Memory
free :: proc(ptr: rawptr) {
    if ptr == nil {
        return
    }
    
    if !heap_initialized {
        cpu.panic("Kernel Heap: Not initialized")
    }
    
    // Get block header
    header := cast(*Block_Header)(uintptr(ptr) - size_of(Block_Header))
    
    // Validate block
    if header.magic != BLOCK_MAGIC {
        log.error("Kernel Heap: Invalid block header at %p", ptr)
        return
    }
    
    if (header.flags & BLOCK_FREE) != 0 {
        log.error("Kernel Heap: Double free at %p", ptr)
        return
    }
    
    // Mark as free
    header.flags |= BLOCK_FREE
    
    total_freed += header.size
    arena_used() -= header.size + size_of(Block_Header)
    
    // Coalesce with next block if free
    if header.next != nil && (header.next.flags & BLOCK_FREE) != 0 {
        header.size += size_of(Block_Header) + header.next.size
        header.next = header.next.next
        if header.next != nil {
            header.next.prev = header
        }
    }
    
    // Coalesce with previous block if free
    if header.prev != nil && (header.prev.flags & BLOCK_FREE) != 0 {
        header.prev.size += size_of(Block_Header) + header.size
        header.prev.next = header.next
        if header.next != nil {
            header.next.prev = header.prev
        }
    }
}


// Reallocate Memory
realloc :: proc(ptr: rawptr, new_size: usize) -> rawptr {
    if ptr == nil {
        return alloc(new_size)
    }
    
    if new_size == 0 {
        free(ptr)
        return nil
    }
    
    header := cast(*Block_Header)(uintptr(ptr) - size_of(Block_Header))
    old_size := header.size
    
    if new_size <= old_size {
        // Shrinking - could split block (optional optimization)
        return ptr
    }
    
    // Growing - allocate new and copy
    new_ptr := alloc(new_size)
    if new_ptr == nil {
        return nil
    }
    
    mem.copy(new_ptr, ptr, old_size)
    free(ptr)
    
    return new_ptr
}


// Find Free Block
find_free_block :: proc(required_size: usize) -> *Block_Header {
    arena := first_arena
    for arena != nil {
        block := arena.free_list
        for block != nil {
            if (block.flags & BLOCK_FREE) != 0 && block.size >= required_size - size_of(Block_Header) {
                return block
            }
            block = block.next
        }
        arena = arena.next
    }
    return nil
}


// Expand Heap
expand_heap :: proc(required_size: usize) -> *Block_Header {
    // Allocate new arena chunk
    chunks_needed := (required_size + HEAP_CHUNK_SIZE - 1) / HEAP_CHUNK_SIZE
    new_arena_size := chunks_needed * HEAP_CHUNK_SIZE
    
    arena_base := virtual.allocate_kernel_virtual(new_arena_size)
    if arena_base == 0 {
        return nil
    }
    
    // Create new arena
    new_arena := cast(*Heap_Arena)(arena_base)
    new_arena.base = arena_base
    new_arena.size = new_arena_size
    new_arena.used = 0
    new_arena.next = nil
    
    // Link to arena list
    arena := first_arena
    while arena.next != nil {
        arena = arena.next
    }
    arena.next = new_arena
    
    // Create free block
    header_size := size_of(Block_Header)
    block := cast(*Block_Header)(arena_base + header_size)
    block.size = new_arena_size - 2 * header_size
    block.flags = BLOCK_FREE
    block.magic = BLOCK_MAGIC
    block.next = nil
    block.prev = nil
    
    new_arena.free_list = block
    
    return block
}


// Get Arena Used Counter
arena_used :: proc() -> *usize {
    return &main_arena.used
}


// Get Heap Statistics
get_stats :: proc() -> (allocated: usize, freed: usize, in_use: usize, arenas: int) {
    arena_count := 0
    arena := first_arena
    for arena != nil {
        arena_count++
        arena = arena.next
    }
    
    return total_allocated, total_freed, total_allocated - total_freed, arena_count
}


// Get Heap Base
get_base :: proc() -> uintptr {
    return main_arena.base
}


// Dump Heap (Debug)
dump :: proc() {
    log.info("=== Heap Dump ===")
    log.info("Allocated: %d bytes", total_allocated)
    log.info("Freed: %d bytes", total_freed)
    log.info("In Use: %d bytes", total_allocated - total_freed)
    
    arena := first_arena
    arena_num := 0
    for arena != nil {
        log.info("Arena %d: base=0x%p, size=%d, used=%d",
                 arena_num, arena.base, arena.size, arena.used)
        
        block := cast(*Block_Header)(arena.base + size_of(Block_Header))
        block_num := 0
        for uintptr(block) < arena.base + arena.size {
            if block.magic == BLOCK_MAGIC {
                state := "used"
                if (block.flags & BLOCK_FREE) != 0 {
                    state = "free"
                }
                log.info("  Block %d: %s, size=%d", block_num, state, block.size)
            }
            block = cast(*Block_Header)(uintptr(block) + size_of(Block_Header) + block.size)
            block_num++
        }
        
        arena = arena.next
        arena_num++
    }
}
