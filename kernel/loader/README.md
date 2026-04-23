# ELF Binary Loader

Complete ELF64 binary loader for TimelessOS supporting static executables.

## Features

### Supported ELF Features
- **ELF64 Format**: Full support for 64-bit ELF executables
- **Program Headers**: Parses and loads PT_LOAD segments
- **Memory Mapping**: Maps segments with correct permissions (R/W/X)
- **User Stack**: Allocates and maps 32KB user stack at high canonical address
- **Entry Point**: Correctly sets process entry point from ELF header
- **Static Binaries**: Primary support for statically linked executables

### ELF Structures Implemented
- `Elf64_Ehdr` - ELF header parsing and validation
- `Elf64_Phdr` - Program header table processing
- `Elf64_Shdr` - Section header table (for future use)
- `Elf64_Sym` - Symbol table structures
- `Elf64_Dyn` - Dynamic section structures
- `Elf64_Rel/Rela` - Relocation entries

### Validation
- Magic number verification (0x7F 'E' 'L' 'F')
- Class check (must be ELF64)
- Endianness check (must be little-endian)
- Type validation (ET_EXEC or ET_DYN)
- Architecture check (must be x86_64)
- Entry point validation

## API Functions

### Core Loading
```odin
// Load ELF from file data buffer
load_elf :: proc(file_data: []u8, process: ^scheduler.Process) -> Load_Result_Code

// Load binary from filesystem path  
load_binary_from_path :: proc(path: string, process: ^scheduler.Process) -> Load_Result_Code

// Create complete process from binary file
create_process :: proc(path: string, name: string) -> ^scheduler.Process
```

### Information Queries
```odin
// Get ELF info without full loading
get_elf_info :: proc(file_data: []u8) -> ?ELF_Info
```

## Usage Example

```odin
import "kernel/loader"

// Method 1: Create process directly from path
process := loader.create_process("/bin/init", "init")
if process != nil {
    scheduler.add_process(process)
}

// Method 2: Manual loading
file_data := fs.read_entire_file("/bin/myapp")
process := scheduler.create_process("myapp")
result := loader.load_elf(file_data, process)

if result == .Success {
    thread := scheduler.create_thread(
        process, 
        process.entry_point, 
        process.stack_pointer
    )
    scheduler.add_thread(thread)
}
```

## Memory Layout

The loader creates the following memory layout for user processes:

```
High Addresses
┌─────────────────────┐
│   User Stack        │ ← 0x7FFF_FFFF_FFFF_FFFF (32KB)
│   (grows downward)  │
├─────────────────────┤
│                     │
│     (free space)    │
│                     │
├─────────────────────┤
│   Code Segment      │ ← ELF PT_LOAD segments
│   Data Segment      │   (mapped with correct perms)
│   BSS Segment       │
├─────────────────────┤
│   (kernel space)    │ ← Higher half kernel
│                     │
└─────────────────────┘
Low Addresses
```

## Page Permissions

Segments are mapped with appropriate permissions based on program header flags:

| Flag | Page Permission |
|------|----------------|
| PF_R | PAGE_READONLY  |
| PF_W | PAGE_WRITABLE  |
| PF_X | PAGE_EXECUTE   |
| All  | PAGE_USER      |

## Error Handling

Returns detailed error codes via `Load_Result_Code`:

- `.Success` - Binary loaded successfully
- `.Invalid_Magic` - Not a valid ELF file
- `.Invalid_Class` - Not 64-bit ELF
- `.Invalid_Endian` - Wrong byte order
- `.Invalid_Type` - Not executable/shared object
- `.Invalid_Machine` - Not x86_64 architecture
- `.Invalid_Entry` - Invalid entry point
- `.No_Load_Segments` - No PT_LOAD segments found
- `.Memory_Allocation_Failed` - Physical page allocation failed
- `.File_Read_Error` - Filesystem read error
- `.Alignment_Error` - Segment alignment issue
- `.Dynamic_Linking_Not_Supported` - Dynamic binary detected (future)

## Limitations & Future Work

### Current Limitations
- Static binaries only (no dynamic linker)
- No shared library loading
- No TLS (Thread Local Storage) implementation
- No ASLR (Address Space Layout Randomization)
- Single initial thread per process

### Planned Enhancements
1. **Dynamic Linking**: Support for `.dynsym`, `.plt`, `.got`
2. **Shared Libraries**: Load and link .so files
3. **TLS Support**: Thread-local storage setup
4. **ASLR**: Randomize load addresses for security
5. **Demand Paging**: Lazy loading of pages
6. **Multi-threading**: Support for pthreads
7. **Position Independent Executables**: Better PIE support

## Integration Points

### With Memory Manager
- Uses `mm.physical_allocator.allocate()` for physical pages
- Calls `mm.map_page()` to map into process address space
- Respects `mm.PAGE_SIZE` alignment requirements

### With Scheduler
- Creates process structure via `scheduler.create_process()`
- Creates initial thread via `scheduler.create_thread()`
- Sets process entry point and stack pointer

### With Filesystem
- Opens files via `fs.open()`
- Reads content via `fs.read()`
- Gets file size via `fs.get_size()`

## Testing

To test the ELF loader:

1. Compile a simple static C program:
```bash
gcc -static -nostdlib test.c -o test.elf
```

2. Copy to filesystem image:
```bash
cp test.elf /workspace/fs/bin/
```

3. Load in kernel:
```odin
process := loader.create_process("/bin/test.elf", "test")
assert(process != nil)
```

## References

- ELF Specification: https://refspecs.linuxfoundation.org/elf/elf.pdf
- System V ABI: https://refspecs.linuxfoundation.org/abi.shtml
- x86_64 psABI: https://refspecs.linuxfoundation.org/elf/x86_64-abi-0.99.pdf
