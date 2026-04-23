/**
 * TimelessOS Process Management
 * 
 * Handles process creation, memory mapping, and user-space transitions.
 * Integrates ELF loader with scheduler for complete process lifecycle.
 */

package kernel

import "core:mem"
import "timeless/scheduler"
import "timeless/mm"
import "timeless/fs"
import "timeless/logging"
import "timeless/arch/x86_64"

// Import ELF loader types
using mm

// Process Creation Flags
Process_Flags :: bit_set {
    User_Mode,
    Create_Stack,
    Load_ELF,
    Inherit_Environment,
}

// Process Creation Attributes
Process_Attrs :: struct {
    name: string,
    path: string,
    flags: Process_Flags,
    priority: i32,
    stack_size: u64,
    environment: []string,
    arguments: []string,
}

// User Stack Info
User_Stack_Info :: struct {
    base: u64,
    top: u64,
    size: u64,
}

USER_STACK_SIZE :: 8 * 1024 * 1024  // 8 MB default user stack

/**
 * Create a new user-space process from an ELF binary.
 * This is the main entry point for loading and executing user programs.
 * 
 * @param path Path to the ELF binary in VFS
 * @param args Command-line arguments
 * @returns PID of created process, or 0 on failure
 */
create_user_process :: proc(path: string, args: []string) -> u32 {
    using logging
    
    log_info("Process: Creating user process from: %s", path)
    
    // Allocate new page directory for process isolation
    page_dir := mm.create_page_directory()
    if page_dir == nil {
        log_error("Process: Failed to create page directory")
        return 0
    }
    
    page_dir_phys := mm.get_physical_address(page_dir)
    
    // Load ELF binary into the new address space
    var elf_info: Elf_Image_Info
    load_result := load_elf(&path, page_dir_phys, &elf_info)
    
    if load_result != .Ok {
        log_error("Process: Failed to load ELF: %s", elf_load_result_to_string(load_result))
        mm.destroy_page_directory(page_dir)
        return 0
    }
    
    // Allocate and map user stack
    stack_info := allocate_user_stack(page_dir, USER_STACK_SIZE)
    if stack_info.base == 0 {
        log_error("Process: Failed to allocate user stack")
        mm.destroy_page_directory(page_dir)
        return 0
    }
    
    log_info("Process: Loaded ELF: Entry=0x%x, Stack=0x%x-0x%x", 
             elf_info.entry_point, stack_info.base, stack_info.top)
    
    // Create process in scheduler with loaded binary info
    pid := scheduler.create_elf_process(
        path,
        elf_info.entry_point,
        page_dir_phys,
        &stack_info,
        args,
    )
    
    if pid == 0 {
        log_error("Process: Scheduler failed to create process")
        // Cleanup: unmap pages and free page directory
        cleanup_failed_process(page_dir, stack_info)
        return 0
    }
    
    log_info("Process: Successfully created process PID=%d", pid)
    return pid
}

/**
 * Allocate user stack in the given page directory.
 * Maps anonymous memory pages with read/write permissions.
 */
allocate_user_stack :: proc(page_dir: ^mm.Page_Directory, size: u64) -> User_Stack_Info {
    using mm
    
    var info: User_Stack_Info
    info.size = size
    
    // Align size to page boundary
    page_count := (size + 4095) / 4096
    
    // Choose a high address for stack (typical: below 3GB mark for compatibility)
    // Stack grows downward, so we allocate from high to low
    stack_top := u64(0x0000_7fff_ffff_f000)  // High canonical address
    stack_base := stack_top - size
    
    // Align base to page boundary
    stack_base &= ~0xfff
    stack_top = stack_base + size
    
    info.base = stack_base
    info.top = stack_top
    
    log_debug("Process: Allocating stack: 0x%x - 0x%x (%d pages)", 
              stack_base, stack_top, page_count)
    
    // Map each page
    curr_addr := stack_base
    for i in 0..<page_count {
        // Allocate physical frame
        phys_frame := phys_alloc()
        if phys_frame == 0 {
            log_error("Process: Out of memory while allocating stack")
            // Partial cleanup would be needed here
            info.base = 0
            return info
        }
        
        // Zero the page (security: prevent information leakage)
        temp_map := kernel_map_page(phys_frame)
        if temp_map != 0 {
            mem.zero(^u8(temp_map), 4096)
            kernel_unmap_page(temp_map)
        }
        
        // Map into user space with R/W permissions, no execute
        flags := PTE_PRESENT | PTE_WRITABLE | PTE_USER | PTE_NO_EXECUTE
        status := map_page(page_dir, curr_addr, phys_frame, flags)
        
        if status != .Ok {
            log_error("Process: Failed to map stack page at 0x%x", curr_addr)
            phys_free(phys_frame)
            info.base = 0
            return info
        }
        
        curr_addr += 4096
    }
    
    log_debug("Process: Stack allocation complete: 0x%x (%d bytes)", stack_base, size)
    return info
}

/**
 * Setup initial user-space context for a new process.
 * Prepares the stack with arguments and environment variables.
 */
setup_initial_context :: proc(thread: ^scheduler.Thread, entry_point: u64, 
                               stack_top: u64, args: []string, env: []string) {
    using scheduler
    
    ctx := &thread.context
    
    // Clear context
    mem.zero(mem.ptr(ctx), size_of(CPU_Context))
    
    // Set instruction pointer to entry point
    ctx.rip = entry_point
    
    // Set stack pointer (stack grows downward)
    // We'll setup the stack with argc, argv, envp later
    ctx.rsp = stack_top
    
    // Set base pointer
    ctx.rbp = 0
    
    // Set flags (interrupts enabled)
    ctx.rflags = 0x202  // IF flag
    
    // Segment selectors for user mode
    ctx.cs = 0x1B  // User code segment (ring 3)
    ctx.ss = 0x23  // User stack segment (ring 3)
    
    // Kernel stack for when the process enters kernel mode
    ctx.kernel_sp = cast(uintptr)(thread.kernel_stack_top)
    
    // Setup stack with arguments (System V AMD64 ABI)
    // Stack layout at process start:
    // [padding]
    // [envp strings]
    // [argv strings]
    // [auxv]
    // [NULL]
    // [envp pointers]
    // [argv pointers]
    // [argc]
    
    setup_user_stack(thread, args, env)
}

/**
 * Setup user stack according to System V AMD64 ABI.
 * This prepares the initial stack frame for execve.
 */
setup_user_stack :: proc(thread: ^scheduler.Thread, args: []string, env: []string) {
    // Simplified implementation - full ABI compliance would need more work
    // For now, we just ensure the stack is properly aligned
    
    ctx := &thread.context
    
    // Align stack to 16 bytes (ABI requirement)
    ctx.rsp &= ~0xf
    
    // Push argc, argv, envp would go here in a full implementation
    // For the first simple init process, we can skip this
    
    log_debug("Process: Initial context setup: RIP=0x%x, RSP=0x%x", ctx.rip, ctx.rsp)
}

/**
 * Cleanup after a failed process creation.
 * Unmaps all pages and frees the page directory.
 */
cleanup_failed_process :: proc(page_dir: ^mm.Page_Directory, stack_info: User_Stack_Info) {
    using mm
    
    // Unmap stack pages
    if stack_info.base != 0 {
        curr := stack_info.base
        end := stack_info.top
        
        for curr < end {
            // Get physical frame
            phys := get_physical_page(page_dir, curr)
            if phys != 0 {
                phys_free(phys)
            }
            
            unmap_page(page_dir, curr)
            curr += 4096
        }
    }
    
    // Destroy page directory
    destroy_page_directory(page_dir)
}

/**
 * Convert ELF load result to string for logging.
 */
elf_load_result_to_string :: proc(result: Elf_Load_Result) -> string {
    switch result {
    case .Ok: return "OK"
    case .Invalid_Magic: return "Invalid ELF magic number"
    case .Invalid_Class: return "Not a 64-bit ELF"
    case .Invalid_Endian: return "Unsupported endianness"
    case .Unsupported_Type: return "Unsupported ELF type"
    case .Read_Error: return "Failed to read file"
    case .Map_Error: return "Failed to map memory"
    case .No_Load_Segments: return "No loadable segments found"
    }
    return "Unknown error"
}

/**
 * Fork current process (copy-on-write implementation).
 * Creates an exact copy of the calling process.
 */
fork_process :: proc() -> u32 {
    using logging
    log_warn("Process: fork() not yet implemented")
    return 0  // Not implemented yet
}

/**
 * Execute a new program in the current process.
 * Replaces the current process image with a new one.
 */
execve :: proc(path: string, args: []string, env: []string) -> i32 {
    using logging
    
    log_info("Process: execve(%s)", path)
    
    // This would:
    // 1. Load new ELF binary
    // 2. Replace current address space
    // 3. Reset heap and stack
    // 4. Jump to new entry point
    
    log_warn("Process: execve() not fully implemented")
    return -1  // Not implemented yet
}

/**
 * Exit current process with given status code.
 */
exit_process :: proc(status: i32) {
    using logging
    log_info("Process: Exiting with status %d", status)
    
    scheduler.exit_current_thread(status)
}

/**
 * Wait for child process to change state.
 */
wait_pid :: proc(pid: u32, status: ^i32) -> u32 {
    using logging
    log_warn("Process: waitpid() not yet implemented")
    return 0  // Not implemented yet
}
