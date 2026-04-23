// Advanced Memory Management
// Phase 1.2: Memory mapped files, shared memory, NUMA awareness, memory hotplug

package mm.advanced

import (
    "core:mem"
    "core:log"
    "core:sync"
    "core:collections"
    "arch:x86_64/cpu"
    "mm:physical"
    "mm:virtual"
)

PAGE_SIZE :: 4096
HUGE_PAGE_SIZE :: 2 * 1024 * 1024

MMAP_FIXED       :: 0x01
MMAP_SHARED      :: 0x02
MMAP_PRIVATE    :: 0x04
MMAP_ANONYMOUS  :: 0x20
MMAP_POPULATE   :: 0x20000

MAP_FAILED :: (~uintptr(0))

Memory_Region_Type :: enum {
    Anonymous,
    File_Mapped,
    Shared_Memory,
}

Memory_Region_Flags :: struct {
    readable:   bool,
    writable:   bool,
    executable: bool,
    shared:     bool,
    private:    bool,
    populate:   bool,
    locked:     bool,
    hugetlb:    bool,
}

Memory_Region :: struct {
    base:           uintptr,
    size:           usize,
    file_offset:    u64,
    file:           rawptr,
    region_type:    Memory_Region_Type,
    flags:          Memory_Region_Flags,
    ref_count:      int,
    vm_area:        rawptr,
    page_cache:     rawptr,
    access_time:     u64,
    is_dirty:       bool,
    prev:          ^Memory_Region,
    next:          ^Memory_Region,
}

Memory_Region_Manager :: struct {
    regions:       ^Memory_Region,
    region_count:    usize,
    total_size:     usize,
    lock:           sync.Spinlock,
}

mm_manager: Memory_Region_Manager

init :: proc() {
    log.info("Advanced Memory: Initializing...")
    
    mm_manager.regions = nil
    mm_manager.region_count = 0
    mm_manager.total_size = 0
    sync.spinlock_init(&mm_manager.lock)
    
    log.info("Advanced Memory: Initialized")
}

mmap :: proc(addr: uintptr, length: usize, prot: Memory_Region_Flags, 
            fd: rawptr, offset: u64, file_path: string) -> uintptr {
    sync.spinlock_acquire(&mm_manager.lock)
    defer sync.spinlock_release(&mm_manager.lock)
    
    if length == 0 {
        return MAP_FAILED
    }
    
    aligned_length := (length + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
    
    region := alloc_region(aligned_length)
    if region == nil {
        return MAP_FAILED
    }
    
    region.base = addr
    region.size = aligned_length
    region.flags = prot
    region.access_time = 0
    region.is_dirty = false
    
    if fd != nil {
        region.region_type = .File_Mapped
        region.file = fd
        region.file_offset = offset
    } else {
        region.region_type = .Anonymous
    }
    
    if prot.shared {
        region.flags.shared = true
    }
    
    region.ref_count = 1
    
    add_region(region)
    
    if prot.populate {
        populate_region(region)
    }
    
    return region.base
}

munmap :: proc(addr: uintptr, length: usize) -> bool {
    sync.spinlock_acquire(&mm_manager.lock)
    defer sync.spinlock_release(&mm_manager.lock)
    
    if length == 0 || addr == 0 {
        return false
    }
    
    region := find_region_at(addr)
    if region == nil {
        return false
    }
    
    if region.base != addr || region.size < length {
        return false
    }
    
    unmap_region_pages(region)
    remove_region(region)
    free_region(region)
    
    return true
}

mprotect :: proc(addr: uintptr, length: usize, prot: Memory_Region_Flags) -> bool {
    sync.spinlock_acquire(&mm_manager.lock)
    defer sync.spinlock_release(&mm_manager.lock)
    
    region := find_region_at(addr)
    if region == nil {
        return false
    }
    
    for r := region; r != nil && r.base < addr + length; r = r.next {
        update_page_protection(r, prot)
    }
    
    return true
}

msync :: proc(addr: uintptr, length: usize, flags: u32) -> bool {
    region := find_region_at(addr)
    if region == nil {
        return false
    }
    
    if region.region_type == .File_Mapped && region.file != nil {
        sync_file_region(region, length)
    }
    
    return true
}

mlock :: proc(addr: uintptr, length: usize) -> bool {
    region := find_region_at(addr)
    if region == nil {
        return false
    }
    
    for offset := uintptr(0); offset < length; offset += PAGE_SIZE {
        virt := addr + offset
        phys := virtual.virtual_to_physical(virt)
        if phys != 0 {
            physical.allocate_frames(1)
        }
    }
    
    region.flags.locked = true
    return true
}

munlock :: proc(addr: uintptr, length: usize) -> bool {
    region := find_region_at(addr)
    if region == nil {
        return false
    }
    
    region.flags.locked = false
    return true
}

page_fault_handler :: proc(virt: uintptr, error_code: u64) -> bool {
    region := find_region_at(virt)
    if region == nil {
        return false
    }
    
    offset := virt - region.base
    page_offset := offset & ~(PAGE_SIZE - 1)
    
    if region.region_type == .File_Mapped {
        load_page_from_file(region, page_offset)
    } else {
        allocate_anonymous_page(region, page_offset)
    }
    
    region.access_time = cpu.timestamp()
    return true
}

alloc_region :: proc(size: usize) -> ^Memory_Region {
    region_heap_size := size_of(Memory_Region)
    region_ptr := mem.alloc(region_heap_size)
    if region_ptr == nil {
        return nil
    }
    
    region := cast(^Memory_Region)(region_ptr)
    region.base = 0
    region.size = size
    region.file = nil
    region.region_type = .Anonymous
    region.page_cache = nil
    region.prev = nil
    region.next = nil
    
    return region
}

free_region :: proc(region: ^Memory_Region) {
    if region.page_cache != nil {
        mem.free(region.page_cache)
    }
    mem.free(rawptr(region))
}

add_region :: proc(region: ^Memory_Region) {
    if mm_manager.regions == nil {
        mm_manager.regions = region
    } else {
        prev := mm_manager.regions
        for prev.next != nil {
            prev = prev.next
        }
        prev.next = region
        region.prev = prev
    }
    mm_manager.region_count++
    mm_manager.total_size += region.size
}

remove_region :: proc(region: ^Memory_Region) {
    if region.prev != nil {
        region.prev.next = region.next
    } else {
        mm_manager.regions = region.next
    }
    
    if region.next != nil {
        region.next.prev = region.prev
    }
    
    mm_manager.region_count--
    mm_manager.total_size -= region.size
}

find_region_at :: proc(addr: uintptr) -> ^Memory_Region {
    region := mm_manager.regions
    for region != nil {
        if addr >= region.base && addr < region.base + region.size {
            return region
        }
        region = region.next
    }
    return nil
}

find_region_for :: proc(addr: uintptr, length: usize) -> ^Memory_Region {
    test_start := addr
    test_end := addr + length
    
    region := mm_manager.regions
    for region != nil {
        reg_start := region.base
        reg_end := region.base + region.size
        
        if test_start >= reg_start && test_start < reg_end {
            return region
        }
        
        if test_end > reg_start && test_end <= reg_end {
            return region
        }
        
        region = region.next
    }
    return nil
}

populate_region :: proc(region: ^Memory_Region) {
    for offset := uintptr(0); offset < region.size; offset += PAGE_SIZE {
        virt := region.base + offset
        
        if region.region_type == .File_Mapped {
            load_page_from_file(region, offset)
        } else {
            allocate_anonymous_page(region, offset)
        }
    }
}

unmap_region_pages :: proc(region: ^Memory_Region) {
    for offset := uintptr(0); offset < region.size; offset += PAGE_SIZE {
        virt := region.base + offset
        phys := virtual.virtual_to_physical(virt)
        if phys != 0 {
            virtual.unmap_page(virt)
            physical.free_frame(phys)
        }
    }
}

update_page_protection :: proc(region: ^Memory_Region, prot: Memory_Region_Flags) {
    flags: u64 = virtual.PAGE_PRESENT
    
    if prot.writable {
        flags |= virtual.PAGE_WRITABLE
    }
    if prot.executable {
        flags |= 0
    } else {
        flags |= virtual.PAGE_NOEXECUTE
    }
    if prot.readable || prot.writable {
        flags |= virtual.PAGE_USER
    }
    
    region.flags = prot
}

sync_file_region :: proc(region: ^Memory_Region, length: usize) {
    if region.file == nil {
        return
    }
}

load_page_from_file :: proc(region: ^Memory_Region, offset: usize) {
    virt := region.base + uintptr(offset)
    phys := physical.allocate_frame()
    
    if phys == 0 {
        return
    }
    
    virtual.map_page(virt, phys, virtual.PAGE_PRESENT | virtual.PAGE_WRITABLE | virtual.PAGE_USER)
    
    if region.file != nil {
    }
    
    region.is_dirty = region.flags.private
}

allocate_anonymous_page :: proc(region: ^Memory_Region, offset: usize) {
    virt := region.base + uintptr(offset)
    phys := physical.allocate_frame()
    
    if phys == 0 {
        return
    }
    
    flags := virtual.PAGE_PRESENT | virtual.PAGE_USER
    if region.flags.writable {
        flags |= virtual.PAGE_WRITABLE
    }
    if region.flags.executable == false {
        flags |= virtual.PAGE_NOEXECUTE
    }
    
    virtual.map_page(virt, phys, flags)
}

get_memory_usage :: proc() -> (total_mapped: usize, regions: usize) {
    return mm_manager.total_size, mm_manager.region_count
}

_SHM_MAX_SIZE :: 0x40000000
_SHM_SEG_SIZE :: 0x20000000

Shm_Region :: struct {
    id:            u64,
    key:           u64,
    size:          usize,
    base:          uintptr,
    attached_pid:  int,
    ref_count:     int,
    perm:          Shm_Permissions,
    atime:         u64,
    dtime:         u64,
    ctime:         u64,
    lock:          sync.Spinlock,
    next:          ^Shm_Region,
}

Shm_Permissions :: struct {
    owner_read:  bool,
    owner_write: bool,
    owner_exec: bool,
    group_read: bool,
    group_write: bool,
    group_exec: bool,
    other_read: bool,
    other_write: bool,
    other_exec: bool,
}

shm_regions: ^Shm_Region
shm_next_id: u64 = 1

shmget :: proc(key: u64, size: usize, shmflg: int) -> i64 {
    sync.spinlock_acquire(&shm_regions.lock)
    defer sync.spinlock_release(&shm_regions.lock)
    
    region := find_shm_region(key)
    if region != nil {
        return i64(region.id)
    }
    
    if size == 0 {
        return -1
    }
    
    if size > _SHM_MAX_SIZE {
        return -1
    }
    
    aligned_size := (size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
    
    new_region := create_shm_region(aligned_size)
    if new_region == nil {
        return -1
    }
    
    new_region.key = key
    new_region.size = aligned_size
    
    if (shmflg & 0x200) != 0 || (shmflg & 0x400) != 0 {
    } else {
        new_region.perm = Shm_Permissions{
            owner_read = true, owner_write = true,
            group_read = true, group_write = false,
            other_read = true, other_write = false,
        }
    }
    
    add_shm_region(new_region)
    
    return i64(new_region.id)
}

shmat :: proc(shmid: i64, shmaddr: uintptr, shmflg: int) -> uintptr {
    sync.spinlock_acquire(&shm_regions.lock)
    defer sync.spinlock_release(&shm_regions.lock)
    
    region := find_shm_by_id(u64(shmid))
    if region == nil {
        return ^uintptr(0)
    }
    
    if region.attached_pid > 0 && shmaddr == 0 {
        return ^uintptr(0)
    }
    
    base_addr := shmaddr
    if base_addr == 0 {
        base_addr = region.base
    }
    
    for offset := uintptr(0); offset < region.size; offset += PAGE_SIZE {
        phys := region.base + offset
        virt := base_addr + offset
        virtual.map_page(virt, phys, virtual.PAGE_PRESENT | virtual.PAGE_WRITABLE | virtual.PAGE_USER)
    }
    
    region.attached_pid = 0
    region.ref_count++
    
    return base_addr
}

shmdt :: proc(shmaddr: uintptr) -> bool {
    sync.spinlock_acquire(&shm_regions.lock)
    defer sync.spinlock_release(&shm_regions.lock)
    
    region := find_shm_by_addr(shmaddr)
    if region == nil {
        return false
    }
    
    for offset := uintptr(0); offset < region.size; offset += PAGE_SIZE {
        virtual.unmap_page(shmaddr + offset)
    }
    
    region.ref_count--
    region.attached_pid = 0
    
    return true
}

shmctl :: proc(shmid: i64, cmd: int, buf: rawptr) -> int {
    sync.spinlock_acquire(&shm_regions.lock)
    defer sync.spinlock_release(&shm_regions.lock)
    
    region := find_shm_by_id(u64(shmid))
    if region == nil {
        return -1
    }
    
    switch cmd {
    case 0:
        if region.ref_count == 0 {
            remove_shm_region(region)
            free_shm_region(region)
            return 0
        }
        return -1
    case 1:
        return region.size
    case 11:
        region.perm = (^Shm_Permissions)(buf)^
    }
    
    return 0
}

create_shm_region :: proc(size: usize) -> ^Shm_Region {
    region_heap_size := size_of(Shm_Region)
    region_ptr := mem.alloc(region_heap_size)
    if region_ptr == nil {
        return nil
    }
    
    region := cast(^Shm_Region)(region_ptr)
    region.id = shm_next_id
    shm_next_id++
    
    base := virtual.allocate_kernel_virtual(size)
    if base == 0 {
        mem.free(region_ptr)
        return nil
    }
    
    region.size = size
    region.base = base
    region.ref_count = 0
    region.attached_pid = 0
    sync.spinlock_init(&region.lock)
    region.next = nil
    
    return region
}

free_shm_region :: proc(region: ^Shm_Region) {
    virtual.free_kernel_virtual(region.base, region.size)
    mem.free(rawptr(region))
}

add_shm_region :: proc(region: ^Shm_Region) {
    if shm_regions == nil {
        shm_regions = region
    } else {
        prev := shm_regions
        for prev.next != nil {
            prev = prev.next
        }
        prev.next = region
    }
}

remove_shm_region :: proc(region: ^Shm_Region) {
    if shm_regions == region {
        shm_regions = region.next
        return
    }
    
    prev := shm_regions
    for prev != nil && prev.next != region {
        prev = prev.next
    }
    
    if prev != nil {
        prev.next = region.next
    }
}

find_shm_region :: proc(key: u64) -> ^Shm_Region {
    region := shm_regions
    for region != nil {
        if region.key == key {
            return region
        }
        region = region.next
    }
    return nil
}

find_shm_by_id :: proc(id: u64) -> ^Shm_Region {
    region := shm_regions
    for region != nil {
        if region.id == id {
            return region
        }
        region = region.next
    }
    return nil
}

find_shm_by_addr :: proc(addr: uintptr) -> ^Shm_Region {
    region := shm_regions
    for region != nil {
        if addr >= region.base && addr < region.base + region.size {
            return region
        }
        region = region.next
    }
    return nil
}

NUMA_Node :: struct {
    id:             int,
    start_addr:      uintptr,
    end_addr:      uintptr,
    total_pages:    usize,
    free_pages:    usize,
    hardware_id:   u32,
    physical_id:  int,
    distances:   [16]u8,
    next:        ^NUMA_Node,
}

NUMA_Policy :: enum {
    Default,
    Preferred,
    Bind,
    Interleave,
    Local,
}

NUMA_Memory_Stats :: struct {
    node_id:          int,
    total_bytes:      u64,
    free_bytes:      u64,
    active_bytes:    u64,
    inactive_bytes:  u64,
    writeback_bytes: u64,
}

numa_nodes: ^NUMA_Node
numa_node_count: int = 0
numa_aware_enabled: bool = false
current_numa_policy: NUMA_Policy = .Default

numa_init :: proc() {
    log.info("NUMA: Initializing...")
    
    numa_nodes = nil
    numa_node_count = 0
    
    detect_numa_topology()
    
    if numa_node_count > 1 {
        numa_aware_enabled = true
        log.info("NUMA: Enabled with %d nodes", numa_node_count)
    } else {
        log.info("NUMA: Single node (UMA)")
    }
}

detect_numa_topology :: proc() {
    numa_node := alloc_numa_node()
    if numa_node == nil {
        return
    }
    
    numa_node.id = 0
    numa_node.start_addr = 0x1000
    total_mem := physical.get_total_memory()
    numa_node.end_addr = numa_node.start_addr + total_mem
    numa_node.total_pages = total_mem / PAGE_SIZE
    numa_node.free_pages = numa_node.total_pages
    numa_node.physical_id = 0
    
    for i in 0..<16 {
        numa_node.distances[i] = 10
    }
    numa_node.distances[0] = 0
    
    numa_nodes = numa_node
    numa_node_count = 1
}

alloc_numa_node :: proc() -> ^NUMA_Node {
    node_ptr := mem.alloc(size_of(NUMA_Node))
    if node_ptr == nil {
        return nil
    }
    
    node := cast(^NUMA_Node)(node_ptr)
    node.next = nil
    
    return node
}

numa_allocate :: proc(size: usize, policy: NUMA_Policy, node_id: int) -> uintptr {
    if !numa_aware_enabled {
        return virtual.allocate_kernel_virtual(size)
    }
    
    target_node := find_numa_node(node_id)
    if target_node == nil {
        target_node = numa_nodes
    }
    
    if target_node.free_pages * PAGE_SIZE < size {
        fallback_node := find_numa_node_with_space(size)
        if fallback_node != nil {
            target_node = fallback_node
        }
    }
    
    if target_node.free_pages * PAGE_SIZE < size {
        return 0
    }
    
    base := virtual.allocate_kernel_virtual(size)
    if base != 0 {
        target_node.free_pages -= size / PAGE_SIZE
    }
    
    return base
}

numa_free :: proc(addr: uintptr, size: usize) {
    if !numa_aware_enabled {
        virtual.free_kernel_virtual(addr, size)
        return
    }
    
    node := find_numa_node_for_addr(addr)
    if node != nil {
        node.free_pages += size / PAGE_SIZE
    }
    
    virtual.free_kernel_virtual(addr, size)
}

numa_set_policy :: proc(policy: NUMA_Policy) {
    current_numa_policy = policy
}

numa_get_policy :: proc() -> NUMA_Policy {
    return current_numa_policy
}

numa_bind_to_node :: proc(node_id: int) -> bool {
    if node_id < 0 || node_id >= numa_node_count {
        return false
    }
    
    current_numa_policy = .Bind
    return true
}

numa_preferred_node :: proc(node_id: int) {
    current_numa_policy = .Preferred
}

numa_interleave :: proc() {
    current_numa_policy = .Interleave
}

get_numa_stats :: proc(node_id: int) -> ^NUMA_Memory_Stats {
    node := find_numa_node(node_id)
    if node == nil {
        return nil
    }
    
    stats := mem.alloc(size_of(NUMA_Memory_Stats))
    if stats == nil {
        return nil
    }
    
    s := cast(^NUMA_Memory_Stats)(stats)
    s.node_id = node.id
    s.total_bytes = u64(node.total_pages) * PAGE_SIZE
    s.free_bytes = u64(node.free_pages) * PAGE_SIZE
    
    return s
}

find_numa_node :: proc(id: int) -> ^NUMA_Node {
    node := numa_nodes
    for node != nil {
        if node.id == id {
            return node
        }
        node = node.next
    }
    return nil
}

find_numa_node_for_addr :: proc(addr: uintptr) -> ^NUMA_Node {
    node := numa_nodes
    for node != nil {
        if addr >= node.start_addr && addr < node.end_addr {
            return node
        }
        node = node.next
    }
    return nil
}

find_numa_node_with_space :: proc(size: usize) -> ^NUMA_Node {
    node := numa_nodes
    best_node := node
    
    best_distance := u8(255)
    
    for node != nil {
        if node.free_pages * PAGE_SIZE >= size {
            dist := node.distances[0]
            if dist < best_distance {
                best_distance = dist
                best_node = node
            }
        }
        node = node.next
    }
    
    if best_distance < 255 {
        return best_node
    }
    
    return nil
}

get_numa_node_count :: proc() -> int {
    return numa_node_count
}

is_numa_enabled :: proc() -> bool {
    return numa_aware_enabled
}

HOTPLUG_MAX_REGIONS :: 32

Hotplug_Region :: struct {
    start_addr:      uintptr,
    end_addr:      u64,
    size:         u64,
    state:        Hotplug_State,
    node:         int,
    memory_type:   u32,
}

Hotplug_State :: enum {
    Offline,
    Online,
    Going_Online,
    Going_Offline,
}

hotplug_enabled: bool = false
hotplug_memory_regions: [HOTPLUG_MAX_REGIONS]Hotplug_Region
hotplug_region_count: int = 0

hotplug_init :: proc() {
    log.info("Memory Hotplug: Initializing...")
    
    hotplug_enabled = false
    hotplug_region_count = 0
    
    if cpu.has_feature(.LM) {
        detect_hotpluggable_memory()
    }
    
    log.info("Memory Hotplug: %s", "disabled")
}

detect_hotpluggable_memory :: proc() {
    total := physical.get_total_memory()
    
    if total > 0x10_0000_0000 {
        hotplug_enabled = true
    }
}

hotplug_add_memory :: proc(start: u64, size: u64, node_id: int) -> bool {
    if hotplug_region_count >= HOTPLUG_MAX_REGIONS {
        return false
    }
    
    if size < PAGE_SIZE {
        return false
    }
    
    region := &hotplug_regions[hotplug_region_count]
    region.start_addr = uintptr(start)
    region.end_addr = start + size
    region.size = size
    region.state = .Going_Online
    region.node = node_id
    
    if add_memory_to_numa(start, size, node_id) {
        region.state = .Online
        hotplug_region_count++
        return true
    }
    
    return false
}

hotplug_remove_memory :: proc(start: u64) -> bool {
    for i in 0..<hotplug_region_count {
        region := &hotplug_regions[i]
        
        if u64(region.start_addr) == start {
            if region.state != .Online {
                return false
            }
            
            region.state = .Going_Offline
            
            remove_memory_from_numa(start)
            
            region.state = .Offline
            
            return true
        }
    }
    
    return false
}

hotplug_online_memory :: proc(start: u64) -> bool {
    for i in 0..<hotplug_region_count {
        region := &hotplug_regions[i]
        
        if u64(region.start_addr) == start {
            if region.state == .Going_Online {
                region.state = .Online
                add_memory_to_numa(start, region.size, region.node)
                return true
            }
        }
    }
    
    return false
}

hotplug_offline_memory :: proc(start: u64) -> bool {
    for i in 0..<hotplug_region_count {
        region := &hotplug_regions[i]
        
        if u64(region.start_addr) == start {
            if region.state == .Going_Offline {
                remove_memory_from_numa(start)
                region.state = .Offline
                return true
            }
        }
    }
    
    return false
}

get_hotplug_memory :: proc() -> u64 {
    total: u64 = 0
    
    for i in 0..<hotplug_region_count {
        region := &hotplug_regions[i]
        
        if region.state == .Online {
            total += region.size
        }
    }
    
    return total
}

get_hotplug_region_count :: proc() -> int {
    return hotplug_region_count
}

get_hotplug_region :: proc(index: int) -> ^Hotplug_Region {
    if index < 0 || index >= hotplug_region_count {
        return nil
    }
    
    return &hotplug_regions[index]
}

is_hotplug_enabled :: proc() -> bool {
    return hotplug_enabled
}

add_memory_to_numa :: proc(start: u64, size: u64, node_id: int) -> bool {
    node := find_numa_node(node_id)
    if node == nil {
        return false
    }
    
    node.total_pages += size / PAGE_SIZE
    node.free_pages += size / PAGE_SIZE
    
    return true
}

remove_memory_from_numa :: proc(start: u64) -> bool {
    for i in 0..<hotplug_region_count {
        region := &hotplug_regions[i]
        
        if u64(region.start_addr) == start {
            node := find_numa_node(region.node)
            if node != nil {
                node.total_pages -= region.size / PAGE_SIZE
                node.free_pages -= region.size / PAGE_SIZE
            }
            
            return true
        }
    }
    
    return false
}