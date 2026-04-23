// Virtual Memory Manager
// x86_64 Paging with 4-level page tables (PML4)

package mm.virtual

import (
    "core:mem"
    "core:log"
    "arch:x86_64/cpu"
    "mm:physical"
)

// Constants
PAGE_SIZE :: 4096
LARGE_PAGE_SIZE :: 2 * 1024 * 1024  // 2MB
HUGE_PAGE_SIZE :: 1024 * 1024 * 1024  // 1GB

ENTRIES_PER_TABLE :: 512

// Page Table Entry Flags
PAGE_PRESENT      :: (1 << 0)
PAGE_WRITABLE     :: (1 << 1)
PAGE_USER         :: (1 << 2)
PAGE_WRITETHROUGH :: (1 << 3)
PAGE_NOCACHE      :: (1 << 4)
PAGE_ACCESSED     :: (1 << 5)
PAGE_DIRTY        :: (1 << 6)
PAGE_PAT          :: (1 << 7)
PAGE_GLOBAL       :: (1 << 8)
PAGE_NOEXECUTE    :: (1 << 63)


// Page Table Structures
Page_Entry :: u64

Page_Table :: struct {
    entries: [ENTRIES_PER_TABLE]Page_Entry,
}

// Virtual Memory Layout (x86_64 Canonical Addresses)
// 0x0000_0000_0000_0000 - 0x0000_7FFF_FFFF_FFFF: Lower half (user space)
// 0xFFFF_8000_0000_0000 - 0xFFFF_FFFF_FFFF_FFFF: Higher half (kernel space)

KERNEL_VIRTUAL_BASE :: 0xFFFF_8000_0000_0000
USER_SPACE_LIMIT ::  0x0000_7FFF_FFFF_FFFF


// Kernel Address Space Layout
KERNEL_IMAGE_BASE ::     KERNEL_VIRTUAL_BASE + 0x0000_0000
KERNEL_HEAP_BASE ::      KERNEL_VIRTUAL_BASE + 0x1000_0000
KERNEL_STACK_BASE ::     KERNEL_VIRTUAL_BASE + 0x2000_0000
MMIO_BASE ::             KERNEL_VIRTUAL_BASE + 0x3000_0000
PHYSICAL_MAPPING_BASE :: KERNEL_VIRTUAL_BASE + 0x4000_0000


// Page Table Hierarchy
Page_Tables :: struct {
    pml4: *Page_Table,  // Level 4
    pdpt: *Page_Table,  // Level 3 (PDPT)
    pd:   *Page_Table,  // Level 2 (PD)
    pt:   *Page_Table,  // Level 1 (PT)
}


// Current address space
current_tables: Page_Tables
kernel_pml4: *Page_Table
physical_offset: uintptr  // Offset for direct physical memory mapping


// Initialize Virtual Memory
init :: proc() {
    log.info("Virtual Memory: Initializing...")
    
    // Allocate page tables from physical allocator
    pml4_phys := physical.allocate_frame()
    pdpt_phys := physical.allocate_frame()
    pd_phys := physical.allocate_frame()
    pt_phys := physical.allocate_frame()
    
    if pml4_phys == 0 {
        cpu.panic("Virtual Memory: Failed to allocate PML4")
    }
    
    // Map physical frames to virtual addresses
    pml4 := cast(*Page_Table)(physical_to_virtual(pml4_phys))
    pdpt := cast(*Page_Table)(physical_to_virtual(pdpt_phys))
    pd := cast(*Page_Table)(physical_to_virtual(pd_phys))
    pt := cast(*Page_Table)(physical_to_virtual(pt_phys))
    
    // Zero out page tables
    mem.zero(mem.ptr(pml4), PAGE_SIZE)
    mem.zero(mem.ptr(pdpt), PAGE_SIZE)
    mem.zero(mem.ptr(pd), PAGE_SIZE)
    mem.zero(mem.ptr(pt), PAGE_SIZE)
    
    current_tables = Page_Tables{
        pml4 = pml4,
        pdpt = pdpt,
        pd = pd,
        pt = pt,
    }
    
    kernel_pml4 = pml4
    
    // Set up identity mapping for physical memory
    identity_map_physical()
    
    // Set up kernel virtual memory regions
    setup_kernel_memory()
    
    // Load CR3 with PML4 physical address
    cpu.write_cr3(pml4_phys)
    
    // Enable paging in CR0
    cr0 := cpu.read_cr0()
    cr0 |= (1 << 31)  // PG - Paging
    cr0 |= (1 << 0)   // PE - Protected Mode
    cpu.write_cr0(cr0)
    
    // Enable Write Protect in CR0
    cr0 |= (1 << 16)
    cpu.write_cr0(cr0)
    
    // Enable SMEP/SMAP in CR4
    cr4 := cpu.read_cr4()
    cr4 |= (1 << 20)  // SMEP
    cr4 |= (1 << 21)  // SMAP
    cpu.write_cr4(cr4)
    
    log.info("Virtual Memory: Paging enabled")
}


// Identity Map Physical Memory
// Maps physical addresses 1:1 to virtual addresses
identity_map_physical :: proc() {
    // Map first 2GB of physical memory
    // This allows accessing physical addresses directly
    for phys := 0; phys < 2 * 1024 * 1024 * 1024; phys += PAGE_SIZE {
        virt := physical_to_virtual(uintptr(phys))
        map_page(virt, phys, PAGE_PRESENT | PAGE_WRITABLE | PAGE_GLOBAL)
    }
    
    physical_offset = PHYSICAL_MAPPING_BASE
}


// Set Up Kernel Memory Regions
setup_kernel_memory :: proc() {
    // Map kernel image (already loaded by bootloader)
    // Map kernel heap
    // Map kernel stacks
    // Map MMIO regions
    
    log.info("Virtual Memory: Kernel layout:")
    log.info("  Image:   0x%p", KERNEL_IMAGE_BASE)
    log.info("  Heap:    0x%p", KERNEL_HEAP_BASE)
    log.info("  Stacks:  0x%p", KERNEL_STACK_BASE)
    log.info("  MMIO:    0x%p", MMIO_BASE)
    log.info("  PhysMap: 0x%p", PHYSICAL_MAPPING_BASE)
}


// Map a Virtual Address to Physical
map_page :: proc(virt: uintptr, phys: uintptr, flags: u64) {
    // Extract page table indices from virtual address
    pml4_idx := (virt >> 39) & 0x1FF
    pdpt_idx := (virt >> 30) & 0x1FF
    pd_idx :=   (virt >> 21) & 0x1FF
    pt_idx :=   (virt >> 12) & 0x1FF
    
    // Get or create PML4 entry
    pml4_entry := current_tables.pml4.entries[pml4_idx]
    if (pml4_entry & PAGE_PRESENT) == 0 {
        // Allocate new PDPT
        pdpt_phys := physical.allocate_frame()
        if pdpt_phys == 0 {
            cpu.panic("Virtual Memory: Failed to allocate PDPT")
        }
        pdpt := cast(*Page_Table)(physical_to_virtual(pdpt_phys))
        mem.zero(mem.ptr(pdpt), PAGE_SIZE)
        
        current_tables.pml4.entries[pml4_idx] = pdpt_phys | PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
        pml4_entry = current_tables.pml4.entries[pml4_idx]
    }
    
    // Get PDPT
    pdpt_addr := pml4_entry & 0x000F_FFFF_FFFF_F000
    pdpt := cast(*Page_Table)(physical_to_virtual(pdpt_addr))
    
    // Get or create PDPT entry
    pdpt_entry := pdpt.entries[pdpt_idx]
    if (pdpt_entry & PAGE_PRESENT) == 0 {
        // Allocate new PD
        pd_phys := physical.allocate_frame()
        if pd_phys == 0 {
            cpu.panic("Virtual Memory: Failed to allocate PD")
        }
        pd := cast(*Page_Table)(physical_to_virtual(pd_phys))
        mem.zero(mem.ptr(pd), PAGE_SIZE)
        
        pdpt.entries[pdpt_idx] = pd_phys | PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
        pdpt_entry = pdpt.entries[pdpt_idx]
    }
    
    // Get PD
    pd_addr := pdpt_entry & 0x000F_FFFF_FFFF_F000
    pd := cast(*Page_Table)(physical_to_virtual(pd_addr))
    
    // Get or create PD entry
    pd_entry := pd.entries[pd_idx]
    if (pd_entry & PAGE_PRESENT) == 0 {
        // Allocate new PT
        pt_phys := physical.allocate_frame()
        if pt_phys == 0 {
            cpu.panic("Virtual Memory: Failed to allocate PT")
        }
        pt := cast(*Page_Table)(physical_to_virtual(pt_phys))
        mem.zero(mem.ptr(pt), PAGE_SIZE)
        
        pd.entries[pd_idx] = pt_phys | PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
        pd_entry = pd.entries[pd_idx]
    }
    
    // Get PT
    pt_addr := pd_entry & 0x000F_FFFF_FFFF_F000
    pt := cast(*Page_Table)(physical_to_virtual(pt_addr))
    
    // Set PT entry
    pt.entries[pt_idx] = phys | flags
}


// Map a Large Page (2MB)
map_large_page :: proc(virt: uintptr, phys: uintptr, flags: u64) {
    // Similar to map_page but uses PD entry directly for 2MB pages
    pml4_idx := (virt >> 39) & 0x1FF
    pdpt_idx := (virt >> 30) & 0x1FF
    pd_idx :=   (virt >> 21) & 0x1FF
    
    // Navigate to PD (same as map_page)
    // ...
    
    // Set PD entry with PS (Page Size) flag
    pd.entries[pd_idx] = phys | flags | (1 << 7)  // PS bit
}


// Unmap a Virtual Address
unmap_page :: proc(virt: uintptr) {
    pml4_idx := (virt >> 39) & 0x1FF
    pdpt_idx := (virt >> 30) & 0x1FF
    pd_idx :=   (virt >> 21) & 0x1FF
    pt_idx :=   (virt >> 12) & 0x1FF
    
    // Navigate to PT
    pml4_entry := current_tables.pml4.entries[pml4_idx]
    if (pml4_entry & PAGE_PRESENT) == 0 {
        return  // Not mapped
    }
    
    pdpt := cast(*Page_Table)(physical_to_virtual(pml4_entry & 0x000F_FFFF_FFFF_FFFF_F000))
    pdpt_entry := pdpt.entries[pdpt_idx]
    if (pdpt_entry & PAGE_PRESENT) == 0 {
        return
    }
    
    pd := cast(*Page_Table)(physical_to_virtual(pdpt_entry & 0x000F_FFFF_FFFF_FFFF_F000))
    pd_entry := pd.entries[pd_idx]
    if (pd_entry & PAGE_PRESENT) == 0 {
        return
    }
    
    pt := cast(*Page_Table)(physical_to_virtual(pd_entry & 0x000F_FFFF_FFFF_FFFF_F000))
    
    // Clear PT entry
    pt.entries[pt_idx] = 0
    
    // Flush TLB
    flush_tlb_entry(virt)
}


// Physical to Virtual Address Conversion
physical_to_virtual :: proc(phys: uintptr) -> uintptr {
    return PHYSICAL_MAPPING_BASE + phys
}


// Virtual to Physical Address Conversion
virtual_to_physical :: proc(virt: uintptr) -> uintptr {
    // Walk page tables to find physical address
    pml4_idx := (virt >> 39) & 0x1FF
    pdpt_idx := (virt >> 30) & 0x1FF
    pd_idx :=   (virt >> 21) & 0x1FF
    pt_idx :=   (virt >> 12) & 0x1FF
    
    pml4_entry := current_tables.pml4.entries[pml4_idx]
    if (pml4_entry & PAGE_PRESENT) == 0 {
        return 0
    }
    
    pdpt := cast(*Page_Table)(physical_to_virtual(pml4_entry & 0x000F_FFFF_FFFF_FFFF_F000))
    pdpt_entry := pdpt.entries[pdpt_idx]
    if (pdpt_entry & PAGE_PRESENT) == 0 {
        return 0
    }
    
    pd := cast(*Page_Table)(physical_to_virtual(pdpt_entry & 0x000F_FFFF_FFFF_FFFF_F000))
    pd_entry := pd.entries[pd_idx]
    if (pd_entry & PAGE_PRESENT) == 0 {
        return 0
    }
    
    // Check for large page
    if (pd_entry & (1 << 7)) != 0 {
        // 2MB page
        phys_base := pd_entry & 0x000F_FFFF_FFE0_0000
        offset := virt & 0x1F_FFFF
        return phys_base + offset
    }
    
    pt := cast(*Page_Table)(physical_to_virtual(pd_entry & 0x000F_FFFF_FFFF_FFFF_F000))
    pt_entry := pt.entries[pt_idx]
    if (pt_entry & PAGE_PRESENT) == 0 {
        return 0
    }
    
    phys_base := pt_entry & 0x000F_FFFF_FFFF_FFFF_F000
    offset := virt & 0xFFF
    return phys_base + offset
}


// Flush TLB Entry
flush_tlb_entry :: proc(virt: uintptr) {
    // Use INVLPG instruction
    asm {
        invlpg [virt]
    }
}


// Flush Entire TLB
flush_tlb :: proc() {
    // Reload CR3
    cr3 := cpu.read_cr3()
    cpu.write_cr3(cr3)
}


// Allocate Kernel Virtual Memory
allocate_kernel_virtual :: proc(size: usize) -> uintptr {
    static kernel_heap_current: uintptr = KERNEL_HEAP_BASE
    
    // Align to page boundary
    aligned_size := (size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
    
    addr := kernel_heap_current
    kernel_heap_current += aligned_size
    
    // Allocate physical frames
    phys := physical.allocate_frames(aligned_size / PAGE_SIZE)
    if phys == 0 {
        return 0
    }
    
    // Map virtual to physical
    for offset := 0; offset < aligned_size; offset += PAGE_SIZE {
        map_page(addr + offset, phys + offset, PAGE_PRESENT | PAGE_WRITABLE | PAGE_GLOBAL)
    }
    
    return addr
}


// Free Kernel Virtual Memory
free_kernel_virtual :: proc(addr: uintptr, size: usize) {
    aligned_size := (size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
    
    for offset := 0; offset < aligned_size; offset += PAGE_SIZE {
        phys := virtual_to_physical(addr + offset)
        unmap_page(addr + offset)
        if phys != 0 {
            physical.free_frame(phys)
        }
    }
}
