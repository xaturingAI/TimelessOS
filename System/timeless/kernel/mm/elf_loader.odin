/**
 * TimelessOS ELF64 Binary Loader
 * 
 * Implements loading of ELF64 executables into user-space memory.
 * Handles header parsing, segment loading, and memory mapping.
 */

package mm

import "core:mem"
import "core:bytes"
import "timeless/arch/x86_64"
import "timeless/fs"
import "timeless/logging"

// ELF64 Constants
ELF_MAGIC :: [4]u8{0x7f, 'E', 'L', 'F'}
ELF_CLASS_64 :: 2
ELF_DATA_LSB :: 1 // Little Endian
ELF_TYPE_EXEC :: 2
ELF_TYPE_DYN :: 3 // Position Independent Executable

ET_EXEC :: 2
ET_DYN :: 3

PT_NULL :: 0
PT_LOAD :: 1
PT_DYNAMIC :: 2
PT_INTERP :: 3
PT_NOTE :: 4
PT_PHDR :: 6

PF_X :: 1
PF_W :: 2
PF_R :: 4

// ELF64 Header Structure
Elf64_Ehdr :: struct {
    e_ident:      [16]u8,
    e_type:       u16,
    e_machine:    u16,
    e_version:    u32,
    e_entry:      u64,
    e_phoff:      u64,
    e_shoff:      u64,
    e_flags:      u32,
    e_ehsize:     u16,
    e_phentsize:  u16,
    e_phnum:      u16,
    e_shentsize:  u16,
    e_shnum:      u16,
    e_shstrndx:   u16,
}

// ELF64 Program Header
Elf64_Phdr :: struct {
    p_type:   u32,
    p_flags:  u32,
    p_offset: u64,
    p_vaddr:  u64,
    p_paddr:  u64,
    p_filesz: u64,
    p_memsz:  u64,
    p_align:  u64,
}

// Load Result
Elf_Load_Result :: enum {
    Ok,
    Invalid_Magic,
    Invalid_Class,
    Invalid_Endian,
    Unsupported_Type,
    Read_Error,
    Map_Error,
    No_Load_Segments,
}

// Loaded Image Info
Elf_Image_Info :: struct {
    entry_point: u64,
    base_addr:   u64,
    mem_size:    u64,
}

/**
 * Load an ELF64 binary from a file into the given page directory.
 * 
 * @param path Path to the binary in VFS
 * @param page_dir Physical address of the target page directory
 * @param info Output structure with entry point and memory info
 * @returns Elf_Load_Result
 */
load_elf :: proc(path: ^string, page_dir: u64, info: ^Elf_Image_Info) -> Elf_Load_Result {
    using logging
    
    // Open file
    file := fs.open(path)
    if file == nil {
        log_error("Loader: Failed to open file: %s", path^)
        return .Read_Error
    }
    defer fs.close(file)

    // Read ELF Header
    var header: Elf64_Ehdr
    read_count := fs.read(file, &header, size_of(header))
    
    if read_count < size_of(header) {
        log_error("Loader: Failed to read ELF header")
        return .Read_Error
    }

    // Validate Magic Number
    if header.e_ident[0] != ELF_MAGIC[0] || 
       header.e_ident[1] != ELF_MAGIC[1] || 
       header.e_ident[2] != ELF_MAGIC[2] || 
       header.e_ident[3] != ELF_MAGIC[3] {
        log_error("Loader: Invalid ELF magic number")
        return .Invalid_Magic
    }

    // Validate Class (64-bit)
    if header.e_ident[4] != ELF_CLASS_64 {
        log_error("Loader: Not a 64-bit ELF")
        return .Invalid_Class
    }

    // Validate Endianness (Little Endian)
    if header.e_ident[5] != ELF_DATA_LSB {
        log_error("Loader: Unsupported endianness")
        return .Invalid_Endian
    }

    // Validate Type
    if header.e_type != ET_EXEC && header.e_type != ET_DYN {
        log_error("Loader: Unsupported ELF type: %d", header.e_type)
        return .Unsupported_Type
    }

    log_info("Loader: ELF Type: %s, Machine: 0x%x, Entry: 0x%x", 
             if header.e_type == ET_EXEC then "EXEC" else "DYN",
             header.e_machine, header.e_entry)

    // Calculate Base Address for PIE
    base_addr: u64 = 0
    if header.e_type == ET_DYN {
        // For PIE, we need to choose a load base (simple implementation: 0x400000)
        base_addr = 0x400000 
    }

    // Read Program Headers
    if header.e_phentsize != size_of(Elf64_Phdr) {
        log_error("Loader: Invalid program header size")
        return .Read_Error
    }

    loaded_segments := 0
    min_vaddr: u64 = 0xffff_ffff_ffff_ffff
    max_end: u64 = 0

    #load_loop: for i in 0..<header.e_phnum {
        // Seek to program header
        offset := header.e_phoff + (u64(i) * u64(header.e_phentsize))
        fs.seek(file, offset, fs.Seek_Whence_Start)

        var phdr: Elf64_Phdr
        if fs.read(file, &phdr, size_of(phdr)) < size_of(phdr) {
            log_error("Loader: Failed to read program header %d", i)
            return .Read_Error
        }

        // Only load PT_LOAD segments
        if phdr.p_type != PT_LOAD {
            continue
        }

        loaded_segments += 1

        // Calculate virtual address
        vaddr := phdr.p_vaddr
        if header.e_type == ET_DYN {
            vaddr += base_addr
        }

        // Align down to page boundary
        start_page := vaddr & ~0xfff
        // Align up to page boundary
        end_page := (vaddr + phdr.p_memsz + 0xfff) & ~0xfff

        if start_page < min_vaddr { min_vaddr = start_page }
        if end_page > max_end { max_end = end_page }

        log_debug("Loader: Mapping segment %d: 0x%x -> 0x%x (flags: 0x%x)", 
                  i, start_page, end_page, phdr.p_flags)

        // Map memory pages
        curr := start_page
        file_offset := phdr.p_offset
        bytes_left_in_file := phdr.p_filesz
        
        for curr < end_page {
            // Allocate physical frame
            phys_frame := phys_alloc()
            if phys_frame == 0 {
                log_error("Loader: Out of physical memory")
                return .Map_Error
            }

            // Clear the page first
            mem.zero(^u8(phys_frame), 4096)

            // Read data from file if available
            to_read := min(4096, bytes_left_in_file)
            if to_read > 0 {
                fs.seek(file, file_offset, fs.Seek_Whence_Start)
                // Map temporarily to copy data (simplified: assuming direct map or copy via temp map)
                // In a real kernel, we'd map this phys_frame into a temporary kernel virtual address
                temp_vaddr := kernel_map_page(phys_frame)
                if temp_vaddr == 0 {
                    phys_free(phys_frame)
                    return .Map_Error
                }
                
                read_bytes := fs.read(file, ^u8(temp_vaddr), int(to_read))
                if read_bytes < to_read {
                    log_warn("Loader: Short read in segment")
                }
                
                kernel_unmap_page(temp_vaddr)
                
                file_offset += u64(read_bytes)
                bytes_left_in_file -= u64(read_bytes)
            }

            // Determine flags
            flags := PTE_USER
            if phdr.p_flags & PF_R != 0 { flags |= PTE_PRESENT }
            if phdr.p_flags & PF_W != 0 { flags |= PTE_WRITABLE }
            if phdr.p_flags & PF_X != 0 { flags |= PTE_NO_EXECUTE } // Inverted logic for NX
            
            // Map into target page directory
            status := map_page(page_dir, curr, phys_frame, flags)
            if status != .Ok {
                log_error("Loader: Failed to map page at 0x%x", curr)
                return .Map_Error
            }

            curr += 4096
        }
    }

    if loaded_segments == 0 {
        log_error("Loader: No loadable segments found")
        return .No_Load_Segments
    }

    // Set output info
    info^.entry_point = header.e_entry
    if header.e_type == ET_DYN {
        info^.entry_point += base_addr
        info^.base_addr = min_vaddr
    } else {
        info^.base_addr = 0
    }
    info^.mem_size = max_end - min_vaddr

    log_info("Loader: Successfully loaded %s, Entry: 0x%x, Size: %d bytes", 
             path^, info^.entry_point, info^.mem_size)

    return .Ok
}

min :: proc(a: u64, b: u64) -> u64 {
    if a < b { return a }
    return b
}
