// System Call Handler Implementation
// Handles system calls from user space

package arch.x86_64.cpu

import (
    "core:log"
    "core:types"
    "src/System/timeless/kernel/scheduler"
)

// Syscall numbers
SYSCALL_READ      :: 0
SYSCALL_WRITE     :: 1
SYSCALL_OPEN      :: 2
SYSCALL_CLOSE     :: 3
SYSCALL_EXIT      :: 60
SYSCALL_FORK      :: 57
SYSCALL_EXECVE    :: 59
SYSCALL_GETPID    :: 39
SYSCALL_YIELD     :: 100  // Custom yield syscall
SYSCALL_GETTID    :: 186

// Syscall frame structure (matches assembly layout)
Syscall_Frame :: struct {
    // Pushed by syscall stub in reverse order
    r15 : u64,
    r14 : u64,
    r13 : u64,
    r12 : u64,
    r11 : u64,  // Saved RFLAGS
    r10 : u64,  // 1st argument
    r9  : u64,  // 6th argument
    r8  : u64,  // 5th argument
    rbp : u64,
    rdi : u64,  // 2nd argument
    rsi : u64,  // 3rd argument
    rdx : u64,  // 4th argument
    rcx : u64,  // Saved RIP
    rbx : u64,
    rax : u64,  // Syscall number / return value
}

// Main syscall handler (called from assembly stub)
syscall_handler :: proc(frame: ^Syscall_Frame) {
    syscall_num := frame.rax
    
    // Execute the appropriate syscall
    result := handle_syscall(syscall_num, frame)
    
    // Set return value
    frame.rax = result
}

// Handle individual syscalls
handle_syscall :: proc(syscall_num: u64, frame: ^Syscall_Frame) -> i64 {
    switch syscall_num {
    case SYSCALL_READ:
        return sys_read(frame.rdi, frame.rsi, frame.rdx)
        
    case SYSCALL_WRITE:
        return sys_write(frame.rdi, frame.rsi, frame.rdx)
        
    case SYSCALL_OPEN:
        return sys_open(frame.rdi, frame.rsi)
        
    case SYSCALL_CLOSE:
        return sys_close(frame.rdi)
        
    case SYSCALL_EXIT:
        sys_exit(i32(frame.rdi))
        return 0
        
    case SYSCALL_GETPID:
        return sys_getpid()
        
    case SYSCALL_YIELD:
        sys_yield()
        return 0
        
    case SYSCALL_GETTID:
        return sys_gettid()
        
    case:
        log.warn("Unknown syscall: %d", syscall_num)
        return -1  // ENOSYS
    }
}

// Syscall implementations

// Read from file descriptor
sys_read :: proc(fd: u64, buf: u64, count: u64) -> i64 {
    // TODO: Implement actual read
    log.debug("SYS_READ: fd=%d, buf=0x%X, count=%d", fd, buf, count)
    return -1  // Not implemented
}

// Write to file descriptor
sys_write :: proc(fd: u64, buf: u64, count: u64) -> i64 {
    // TODO: Implement actual write
    log.debug("SYS_WRITE: fd=%d, buf=0x%X, count=%d", fd, buf, count)
    return -1  // Not implemented
}

// Open file
sys_open :: proc(path: u64, flags: u64) -> i64 {
    // TODO: Implement actual open
    log.debug("SYS_OPEN: path=0x%X, flags=0x%X", path, flags)
    return -1  // Not implemented
}

// Close file descriptor
sys_close :: proc(fd: u64) -> i64 {
    // TODO: Implement actual close
    log.debug("SYS_CLOSE: fd=%d", fd)
    return -1  // Not implemented
}

// Exit current process
sys_exit :: proc(status: i32) {
    log.info("Process exiting with status: %d", status)
    // TODO: Implement process termination
    scheduler.exit_current_process(status)
}

// Get process ID
sys_getpid :: proc() -> i64 {
    // TODO: Return actual PID
    return 1  // Placeholder
}

// Yield CPU to scheduler
sys_yield :: proc() {
    scheduler.yield_current()
}

// Get thread ID
sys_gettid :: proc() -> i64 {
    // TODO: Return actual TID
    return 1  // Placeholder
}

// Initialize syscall interface
init_syscalls :: proc() {
    log.info("System call interface initialized")
}
