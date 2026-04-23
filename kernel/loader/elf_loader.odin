/**
 * ELF Binary Loader for TimelessOS
 * 
 * Supports ELF64 executables with PT_LOAD segments
 * Handles static binaries initially, dynamic linking planned for future
 */

package loader

import "core/mem"
import "core/math"
import "kernel/arch/x86_64"
import "kernel/mm"
import "kernel/fs"
import "kernel/scheduler"

// ELF Magic number
ELF_MAGIC :: [4]u8{0x7f, 'E', 'L', 'F'}

// ELF Class
ELF_CLASS_NONE :: 0
ELF_CLASS_32   :: 1
ELF_CLASS_64   :: 2

// ELF Data encoding
ELF_DATA_NONE :: 0
ELF_DATA_LSB  :: 1  // Little endian
ELF_DATA_MSB  :: 2  // Big endian

// ELF Type
ET_NONE   :: 0
ET_REL    :: 1  // Relocatable file
ET_EXEC   :: 2  // Executable file
ET_DYN    :: 3  // Shared object file
ET_CORE   :: 4  // Core file

// ELF Machine
EM_NONE   :: 0
EM_386    :: 3
EM_X86_64 :: 62

// Program Header Types
PT_NULL    :: 0
PT_LOAD    :: 1
PT_DYNAMIC :: 2
PT_INTERP  :: 3
PT_NOTE    :: 4
PT_SHLIB   :: 5
PT_PHDR    :: 6
PT_TLS     :: 7

// Program Header Flags
PF_X :: 0x1  // Execute
PF_W :: 0x2  // Write
PF_R :: 0x4  // Read

// Section Header Types
SHT_NULL     :: 0
SHT_PROGBITS :: 1
SHT_SYMTAB   :: 2
SHT_STRTAB   :: 3
SHT_RELA     :: 4
SHT_HASH     :: 5
SHT_DYNAMIC  :: 6
SHT_NOTE     :: 7
SHT_NOBITS   :: 8
SHT_REL      :: 9
SHT_DYNSYM   :: 11

// ELF64 Header structure
Elf64_Ehdr :: struct {
    e_ident     : [16]u8,   // ELF identification
    e_type      : u16,      // Object file type
    e_machine   : u16,      // Architecture
    e_version   : u32,      // Object file version
    e_entry     : u64,      // Entry point address
    e_phoff     : u64,      // Program header table offset
    e_shoff     : u64,      // Section header table offset
    e_flags     : u32,      // Processor-specific flags
    e_ehsize    : u16,      // ELF header size
    e_phentsize : u16,      // Program header entry size
    e_phnum     : u16,      // Number of program headers
    e_shentsize : u16,      // Section header entry size
    e_shnum     : u16,      // Number of section headers
    e_shstrndx  : u16,      // Section name string table index
}

// ELF64 Program Header structure
Elf64_Phdr :: struct {
    p_type   : u32,    // Segment type
    p_flags  : u32,    // Segment flags
    p_offset : u64,    // Offset in file
    p_vaddr  : u64,    // Virtual address in memory
    p_paddr  : u64,    // Physical address (if relevant)
    p_filesz : u64,    // Size in file
    p_memsz  : u64,    // Size in memory
    p_align  : u64,    // Alignment
}

// ELF64 Section Header structure
Elf64_Shdr :: struct {
    sh_name      : u32,   // Section name
    sh_type      : u32,   // Section type
    sh_flags     : u64,   // Section flags
    sh_addr      : u64,   // Address in memory
    sh_offset    : u64,   // Offset in file
    sh_size      : u64,   // Size of section
    sh_link      : u32,   // Link to another section
    sh_info      : u32,   // Additional information
    sh_addralign : u64,   // Alignment
    sh_entsize   : u64,   // Entry size if section holds table
}

// ELF64 Symbol structure
Elf64_Sym :: struct {
    st_name  : u32,   // Symbol name
    st_info  : u8,    // Type and binding attributes
    st_other : u8,    // Reserved
    st_shndx : u16,   // Section table index
    st_value : u64,   // Symbol value
    st_size  : u64,   // Size of associated data
}

// ELF64 Dynamic structure
Elf64_Dyn :: struct {
    d_tag : i64,   // Dynamic entry type
    d_val : u64,   // Integer or address value
}

// ELF64 Relocation structures
Elf64_Rel :: struct {
    r_offset : u64,   // Location to be relocated
    r_info   : u64,   // Relocation type and symbol index
}

Elf64_Rela :: struct {
    r_offset : u64,   // Location to be relocated
    r_info   : u64,   // Relocation type and symbol index
    r_addend : i64,   // Addend
}

// Relocation type macros for x86_64
ELF64_R_SYM :: macro(r_info: u64) -> u32 { cast(u32, r_info >> 32) }
ELF64_R_TYPE :: macro(r_info: u64) -> u32 { cast(u32, r_info & 0xFFFFFFFF) }

// Relocation types for x86_64
R_X86_64_NONE       :: 0
R_X86_64_64         :: 1
R_X86_64_PC32       :: 2
R_X86_64_GOT32      :: 3
R_X86_64_PLT32      :: 4
R_X86_64_COPY       :: 5
R_X86_64_GLOB_DAT   :: 6
R_X86_64_JUMP_SLOT  :: 7
R_X86_64_RELATIVE   :: 8
R_X86_64_GOTPCREL   :: 9

// Load result codes
Load_Result_Code :: enum {
    Success,
    Invalid_Magic,
    Invalid_Class,
    Invalid_Endian,
    Invalid_Type,
    Invalid_Machine,
    Invalid_Entry,
    No_Load_Segments,
    Memory_Allocation_Failed,
    File_Read_Error,
    Alignment_Error,
    Dynamic_Linking_Not_Supported,
}

// ELF binary information
ELF_Info :: struct {
    entry_point    : u64,
    base_address   : u64,
    end_address    : u64,
    is_dynamic     : bool,
    has_interp     : bool,
    interp_path    : [256]u8,
    needs_tls      : bool,
    tls_align      : u64,
    tls_memsz      : u64,
}

// Load context for tracking state during loading
Load_Context :: struct {
    file_data      : []u8,
    info           : ELF_Info,
    process        : ^scheduler.Process,
    page_directory : mm.Page_Directory,
}

// Validate ELF header
validate_elf_header :: proc(ehdr: ^Elf64_Ehdr) -> Load_Result_Code {
    // Check magic number
    if ehdr.e_ident[0..4] != ELF_MAGIC {
        return .Invalid_Magic
    }
    
    // Check class (must be 64-bit)
    if ehdr.e_ident[4] != ELF_CLASS_64 {
        return .Invalid_Class
    }
    
    // Check data encoding (must be little endian)
    if ehdr.e_ident[5] != ELF_DATA_LSB {
        return .Invalid_Endian
    }
    
    // Check type (must be executable or shared object)
    if ehdr.e_type != ET_EXEC && ehdr.e_type != ET_DYN {
        return .Invalid_Type
    }
    
    // Check machine (must be x86_64)
    if ehdr.e_machine != EM_X86_64 {
        return .Invalid_Machine
    }
    
    // Check entry point
    if ehdr.e_entry == 0 && ehdr.e_type == ET_EXEC {
        return .Invalid_Entry
    }
    
    return .Success
}

// Map segment permissions to page flags
segment_to_page_flags :: proc(flags: u32) -> mm.Page_Flags {
    page_flags := mm.PAGE_PRESENT | mm.PAGE_USER
    
    if flags & PF_X != 0 {
        page_flags |= mm.PAGE_EXECUTE
    }
    if flags & PF_W != 0 {
        page_flags |= mm.PAGE_WRITABLE
    } else {
        page_flags |= mm.PAGE_READONLY
    }
    
    return page_flags
}

// Load a single PT_LOAD segment
load_segment :: proc(ctx: ^Load_Context, phdr: ^Elf64_Phdr) -> Load_Result_Code {
    // Calculate aligned addresses
    page_size := mm.PAGE_SIZE as u64
    
    mem_start := math.align_down(phdr.p_vaddr, page_size)
    mem_end := math.align_up(phdr.p_vaddr + phdr.p_memsz, page_size)
    
    file_start := math.align_down(phdr.p_offset, page_size)
    file_end := phdr.offset + phdr.filesz
    
    // Map pages for this segment
    current_vaddr := mem_start
    current_paddr := file_start
    
    for current_vaddr < mem_end {
        // Allocate physical page
        phys_page := mm.physical_allocator.allocate(1)
        if phys_page == 0 {
            return .Memory_Allocation_Failed
        }
        
        // Determine how much data to copy from file
        file_offset_in_page := current_paddr - math.align_down(current_paddr, page_size)
        copy_size := int(math.min(page_size - file_offset_in_page, phdr.p_memsz - (current_vaddr - phdr.p_vaddr)))
        
        // Clear the page first
        mem.memset(cast(^u8, phys_page), 0, int(page_size))
        
        // Copy data from file if within file bounds
        if current_paddr < phdr.p_offset + phdr.p_filesz {
            src_offset := current_paddr - phdr.p_offset
            if src_offset < phdr.p_filesz {
                actual_copy_size := int(math.min(copy_size, phdr.p_filesz - src_offset))
                if src_offset + actual_copy_size <= len(ctx.file_data) {
                    mem.memcpy(
                        cast(^u8, phys_page) + file_offset_in_page,
                        ctx.file_data[src_offset..],
                        actual_copy_size,
                    )
                }
            }
        }
        
        // Map page into process address space
        page_flags := segment_to_page_flags(phdr.p_flags)
        if !mm.map_page(ctx.page_directory, current_vaddr, phys_page, page_flags) {
            mm.physical_allocator.free(phys_page, 1)
            return .Memory_Allocation_Failed
        }
        
        current_vaddr += page_size
        current_paddr += page_size
    }
    
    return .Success
}

// Handle dynamic section (placeholder for now)
handle_dynamic_section :: proc(ctx: ^Load_Context, dyn_offset: u64, dyn_size: u64) -> Load_Result_Code {
    // For now, we only support static binaries
    // Dynamic linking will be implemented in future versions
    return .Dynamic_Linking_Not_Supported
}

// Parse program headers and load segments
parse_program_headers :: proc(ctx: ^Load_Context, ehdr: ^Elf64_Ehdr) -> Load_Result_Code {
    if ehdr.e_phnum == 0 || ehdr.e_phoff == 0 {
        return .No_Load_Segments
    }
    
    phdrs := cast([*]Elf64_Phdr, ctx.file_data[ehdr.e_phoff:])
    
    has_load_segment := false
    min_vaddr := u64(max_u64)
    max_vaddr := u64(0)
    
    // First pass: validate and find load segments
    for i := 0; i < int(ehdr.e_phnum); i++ {
        phdr := &phdrs[i]
        
        switch phdr.p_type {
        case PT_LOAD:
            has_load_segment = true
            
            if phdr.p_vaddr < min_vaddr {
                min_vaddr = phdr.p_vaddr
            }
            if phdr.p_vaddr + phdr.p_memsz > max_vaddr {
                max_vaddr = phdr.p_vaddr + phdr.p_memsz
            }
            
        case PT_INTERP:
            ctx.info.has_interp = true
            if phdr.p_filesz < len(ctx.info.interp_path) {
                mem.memcpy(ctx.info.interp_path[:], ctx.file_data[phdr.p_offset:], int(phdr.p_filesz))
            }
            
        case PT_TLS:
            ctx.info.needs_tls = true
            ctx.info.tls_align = phdr.p_align
            ctx.info.tls_memsz = phdr.p_memsz
            
        case PT_DYNAMIC:
            ctx.info.is_dynamic = true
            // Store for later processing
        }
    }
    
    if !has_load_segment {
        return .No_Load_Segments
    }
    
    ctx.info.base_address = min_vaddr
    ctx.info.end_address = max_vaddr
    
    // Second pass: load PT_LOAD segments
    for i := 0; i < int(ehdr.e_phnum); i++ {
        phdr := &phdrs[i]
        
        if phdr.p_type == PT_LOAD {
            result := load_segment(ctx, phdr)
            if result != .Success {
                return result
            }
        }
    }
    
    // Handle dynamic section if present
    if ctx.info.is_dynamic {
        for i := 0; i < int(ehdr.e_phnum); i++ {
            phdr := &phdrs[i]
            if phdr.p_type == PT_DYNAMIC {
                result := handle_dynamic_section(ctx, phdr.p_offset, phdr.p_filesz)
                if result != .Success {
                    // For now, just warn but continue for static binaries
                    // In future, this should fail for truly dynamic binaries
                }
            }
        }
    }
    
    return .Success
}

// Setup user stack for the process
setup_user_stack :: proc(ctx: ^Load_Context, entry_point: u64) -> bool {
    page_size := mm.PAGE_SIZE as u64
    stack_size := 8 * page_size  // 32KB default stack
    stack_top := u64(0x7FFF_FFFF_FFFF_FFFF)  // High canonical address
    
    // Align stack top
    stack_top = math.align_down(stack_top, page_size)
    stack_bottom := stack_top - stack_size
    
    // Allocate and map stack pages
    current_vaddr := stack_bottom
    for current_vaddr < stack_top {
        phys_page := mm.physical_allocator.allocate(1)
        if phys_page == 0 {
            return false
        }
        
        // Clear the page
        mem.memset(cast(^u8, phys_page), 0, int(page_size))
        
        // Map as user read-write, no execute
        page_flags := mm.PAGE_PRESENT | mm.PAGE_USER | mm.PAGE_WRITABLE | mm.PAGE_READONLY
        if !mm.map_page(ctx.page_directory, current_vaddr, phys_page, page_flags) {
            mm.physical_allocator.free(phys_page, 1)
            return false
        }
        
        current_vaddr += page_size
    }
    
    // Store stack information in process
    ctx.process.stack_base = stack_bottom
    ctx.process.stack_top = stack_top
    ctx.process.stack_pointer = stack_top
    
    return true
}

// Load ELF binary from file data
load_elf :: proc(file_data: []u8, process: ^scheduler.Process) -> Load_Result_Code {
    if len(file_data) < size_of(Elf64_Ehdr) {
        return .File_Read_Error
    }
    
    // Initialize context
    var ctx : Load_Context
    ctx.file_data = file_data
    ctx.process = process
    ctx.page_directory = process.page_directory
    
    // Get ELF header
    ehdr := cast(^Elf64_Ehdr, &file_data[0])
    
    // Validate header
    result := validate_elf_header(ehdr)
    if result != .Success {
        return result
    }
    
    // Set initial entry point
    ctx.info.entry_point = ehdr.e_entry
    
    // Parse and load program headers
    result = parse_program_headers(&ctx, ehdr)
    if result != .Success {
        return result
    }
    
    // Setup user stack
    if !setup_user_stack(&ctx, ctx.info.entry_point) {
        return .Memory_Allocation_Failed
    }
    
    // Update process information
    process.entry_point = ctx.info.entry_point
    process.base_address = ctx.info.base_address
    process.end_address = ctx.info.end_address
    process.is_dynamic = ctx.info.is_dynamic
    
    return .Success
}

// Load binary from filesystem path
load_binary_from_path :: proc(path: string, process: ^scheduler.Process) -> Load_Result_Code {
    // Open file
    file := fs.open(path, .O_RDONLY)
    if file == nil {
        return .File_Read_Error
    }
    defer fs.close(file)
    
    // Get file size
    file_size := fs.get_size(file)
    if file_size <= 0 {
        return .File_Read_Error
    }
    
    // Allocate buffer for file content
    buffer := make([]u8, int(file_size))
    defer delete(buffer)
    
    // Read entire file into memory
    bytes_read := fs.read(file, buffer)
    if bytes_read != int(file_size) {
        return .File_Read_Error
    }
    
    // Load ELF from buffer
    return load_elf(buffer, process)
}

// Create and load a new process from binary
create_process :: proc(path: string, name: string) -> ^scheduler.Process {
    // Create new process structure
    process := scheduler.create_process(name)
    if process == nil {
        return nil
    }
    
    // Allocate page directory for process
    page_dir := mm.create_page_directory()
    if page_dir == 0 {
        scheduler.destroy_process(process)
        return nil
    }
    
    process.page_directory = page_dir
    
    // Load binary
    result := load_binary_from_path(path, process)
    if result != .Success {
        mm.destroy_page_directory(page_dir)
        scheduler.destroy_process(process)
        return nil
    }
    
    // Create initial thread
    thread := scheduler.create_thread(process, process.entry_point, process.stack_pointer)
    if thread == nil {
        mm.destroy_page_directory(page_dir)
        scheduler.destroy_process(process)
        return nil
    }
    
    // Add thread to process
    process.threads[0] = thread
    process.thread_count = 1
    
    return process
}

// Get ELF info from loaded binary
get_elf_info :: proc(file_data: []u8) -> ?ELF_Info {
    if len(file_data) < size_of(Elf64_Ehdr) {
        return nil
    }
    
    ehdr := cast(^Elf64_Ehdr, &file_data[0])
    
    if validate_elf_header(ehdr) != .Success {
        return nil
    }
    
    var info : ELF_Info
    info.entry_point = ehdr.e_entry
    
    // Quick scan for basic info without full load
    phdrs := cast([*]Elf64_Phdr, file_data[ehdr.e_phoff:])
    for i := 0; i < int(ehdr.e_phnum); i++ {
        phdr := &phdrs[i]
        switch phdr.p_type {
        case PT_INTERP:
            info.has_interp = true
        case PT_TLS:
            info.needs_tls = true
            info.tls_align = phdr.p_align
            info.tls_memsz = phdr.p_memsz
        case PT_DYNAMIC:
            info.is_dynamic = true
        }
    }
    
    return info
}
