// Process Scheduler
// Core scheduling functionality for TimelessOS
// Implements: Round-robin with priority, context switching, ready queues

package scheduler

import (
    "core:mem"
    "core:log"
    "core:sync"
    "arch:x86_64/cpu"
    "mm:heap"
    "mm:virtual"
)

// ============================================================================
// Constants and Types
// ============================================================================

MAX_PROCESSES :: 256
MAX_THREADS_PER_PROCESS :: 1024
KERNEL_STACK_SIZE :: 16384  // 16 KB per thread
USER_STACK_SIZE :: 8388608  // 8 MB per user thread
SCHEDULER_QUANTUM_MS :: 10  // Time slice in milliseconds

// Process States
Process_State :: enum {
    Unused,
    Running,
    Ready,
    Blocked,
    Terminated,
    Zombie,
}

// Thread States
Thread_State :: enum {
    Unused,
    Running,
    Ready,
    Blocked,
    Terminated,
}

// Scheduling Policies
Sched_Policy :: enum {
    FIFO,
    Round_Robin,
    Priority,
    Realtime,
}

// CPU Register Context (saved during context switch)
CPU_Context :: struct {
    // General purpose registers
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    
    // Instruction pointer and flags
    rip: u64,
    rflags: u64,
    
    // Stack pointer
    rsp: u64,
    
    // Segment selectors
    cs: u64,
    ss: u64,
    
    // Floating point / SIMD state (FPU, SSE, AVX)
    fp_state: [512]u8,  // FXSAVE area
    
    // Kernel stack pointer (for user threads)
    kernel_sp: u64,
}

// Thread Control Block
Thread :: struct {
    tid: u32,                    // Thread ID
    pid: u32,                    // Parent Process ID
    state: Thread_State,
    policy: Sched_Policy,
    priority: i32,               // Higher = more important (-20 to 20)
    nice: i32,                   // Nice value (0-20, lower = higher priority)
    
    // CPU context for context switching
    context: CPU_Context,
    
    // Stack information
    kernel_stack_base: rawptr,
    kernel_stack_top: rawptr,
    user_stack_base: rawptr,
    user_stack_size: usize,
    
    // Scheduling information
    remaining_quantum: i64,      // Remaining time slices
    total_runtime: i64,          // Total CPU time used
    wait_time: i64,              // Time spent waiting
    last_run_time: i64,          // Last time this thread ran
    
    // Thread-specific data
    tls_base: rawptr,            // Thread Local Storage base
    
    // Blocking information
    blocked_on: rawptr,          // What the thread is blocked on (mutex, semaphore, etc.)
    wake_time: i64,              // Time to wake up (for sleep)
    
    // Link for ready queue
    next: *Thread,
    prev: *Thread,
}

// Process Control Block
Process :: struct {
    pid: u32,                    // Process ID
    ppid: u32,                   // Parent Process ID
    state: Process_State,
    
    // Process identity
    name: string,
    cmd: string,
    
    // Memory management
    page_directory: virtual.Page_Directory,
    memory_map: []Memory_Region,
    
    // Thread management
    threads: []*Thread,
    thread_count: i32,
    main_thread: *Thread,
    
    // Resource limits
    max_threads: i32,
    open_files: []File_Descriptor,
    
    // Scheduling
    priority: i32,
    nice: i32,
    
    // Process relationships
    children: []u32,             // Child PIDs
    group_id: u32,               // Process group ID
    session_id: u32,             // Session ID
    
    // Exit information
    exit_code: i32,
    exit_time: i64,
    
    // Statistics
    start_time: i64,
    cpu_time: i64,
}

// Memory Region
Memory_Region :: struct {
    base: rawptr,
    size: usize,
    flags: u32,
    type: u32,
}

// File Descriptor
File_Descriptor :: struct {
    fd: i32,
    // ... file descriptor details
}

// Runqueue (per-CPU ready queue)
Runqueue :: struct {
    lock: sync.Spinlock,
    head: *Thread,
    tail: *Thread,
    count: i32,
    
    // Priority array for O(1) scheduling
    priority_queue: [40]*Thread,  // Priorities -20 to +19
}

// Scheduler State
Scheduler :: struct {
    initialized: bool,
    current_thread: *Thread,
    idle_thread: *Thread,
    
    // Global process table
    processes: [MAX_PROCESSES]Process,
    process_count: i32,
    next_pid: u32,
    
    // Global thread table
    threads: [MAX_PROCESSES * MAX_THREADS_PER_PROCESS]Thread,
    thread_count: i32,
    next_tid: u32,
    
    // Per-CPU runqueues
    runqueues: [16]Runqueue,  // Support up to 16 CPUs
    cpu_count: i32,
    
    // Scheduling statistics
    context_switches: i64,
    schedule_calls: i64,
    timer_ticks: i64,
    
    // Current tick counter
    tick_count: i64,
    
    // Scheduler lock
    lock: sync.Spinlock,
}

// ============================================================================
// Global State
// ============================================================================

scheduler: Scheduler

// ============================================================================
// Initialization
// ============================================================================

init :: proc() {
    log.info("Scheduler: Initializing...")
    
    // Zero out scheduler state
    mem.zero(mem.ptr(&scheduler), size_of(Scheduler))
    
    // Initialize per-CPU runqueues
    scheduler.cpu_count = 1  // TODO: Detect actual CPU count
    for i in 0..<scheduler.cpu_count {
        scheduler.runqueues[i].lock = sync.Spinlock{}
        scheduler.runqueues[i].head = nil
        scheduler.runqueues[i].tail = nil
        scheduler.runqueues[i].count = 0
    }
    
    // Create idle thread (runs when nothing else can)
    create_idle_thread()
    
    // Set initial PID/TID
    scheduler.next_pid = 1
    scheduler.next_tid = 1
    
    scheduler.initialized = true
    
    log.info("Scheduler: Initialized with %d CPUs", scheduler.cpu_count)
    log.info("Scheduler: Idle thread created")
}

// ============================================================================
// Process Creation
// ============================================================================

// Create a new process
create_process :: proc(name: string, entry_point: uintptr, user_mode: bool) -> u32 {
    if !scheduler.initialized {
        log.error("Scheduler: Not initialized")
        return 0
    }
    
    scheduler.lock.acquire()
    defer scheduler.lock.release()
    
    // Find free process slot
    pid := find_free_process_slot()
    if pid == 0 {
        log.error("Scheduler: No free process slots")
        return 0
    }
    
    proc := &scheduler.processes[pid]
    
    // Initialize process
    proc.pid = pid
    proc.ppid = get_current_pid()
    proc.state = .Ready
    proc.name = name
    proc.priority = 0
    proc.nice = 0
    proc.thread_count = 0
    proc.max_threads = MAX_THREADS_PER_PROCESS
    proc.start_time = get_tick_count()
    
    // Set up memory space
    if user_mode {
        proc.page_directory = virtual.create_page_directory()
    }
    
    // Create main thread
    thread := create_thread_internal(pid, entry_point, user_mode)
    if thread == nil {
        log.error("Scheduler: Failed to create main thread")
        scheduler.processes[pid].state = .Unused
        return 0
    }
    
    proc.main_thread = thread
    proc.threads = append(proc.threads, thread)
    proc.thread_count = 1
    
    log.info("Scheduler: Created process '%s' (PID=%d)", name, pid)
    
    return pid
}

/**
 * Create a process from a loaded ELF binary.
 * This is the main entry point for loading user programs.
 */
create_elf_process :: proc(name: string, entry_point: u64, page_dir_phys: u64, 
                           stack_info: ^User_Stack_Info, args: []string) -> u32 {
    if !scheduler.initialized {
        log.error("Scheduler: Not initialized")
        return 0
    }
    
    scheduler.lock.acquire()
    defer scheduler.lock.release()
    
    // Find free process slot
    pid := find_free_process_slot()
    if pid == 0 {
        log.error("Scheduler: No free process slots")
        return 0
    }
    
    proc := &scheduler.processes[pid]
    
    // Initialize process
    proc.pid = pid
    proc.ppid = 0  // Init process has no parent
    proc.state = .Ready
    proc.name = name
    proc.priority = 0
    proc.nice = 0
    proc.thread_count = 0
    proc.max_threads = MAX_THREADS_PER_PROCESS
    proc.start_time = get_tick_count()
    
    // Set up memory space with provided page directory
    proc.page_directory.physical_addr = page_dir_phys
    proc.page_directory.virtual_addr = 0  // Will be mapped when switched to
    
    // Create main thread with ELF entry point
    thread := create_elf_thread_internal(pid, entry_point, stack_info, args)
    if thread == nil {
        log.error("Scheduler: Failed to create main thread for ELF")
        scheduler.processes[pid].state = .Unused
        return 0
    }
    
    proc.main_thread = thread
    proc.threads = append(proc.threads, thread)
    proc.thread_count = 1
    
    log.info("Scheduler: Created ELF process '%s' (PID=%d, Entry=0x%x)", name, pid, entry_point)
    
    return pid
}

find_free_process_slot :: proc() -> u32 {
    for i in 1..<MAX_PROCESSES {
        if scheduler.processes[i].state == .Unused || 
           scheduler.processes[i].state == .Zombie {
            return u32(i)
        }
    }
    return 0
}

// User Stack Info (forward declaration for ELF process creation)
User_Stack_Info :: struct {
    base: u64,
    top: u64,
    size: u64,
}

// ============================================================================
// Thread Creation
// ============================================================================

create_thread :: proc(entry_point: uintptr, user_mode: bool) -> u32 {
    pid := get_current_pid()
    thread := create_thread_internal(pid, entry_point, user_mode)
    
    if thread != nil {
        return thread.tid
    }
    return 0
}

/**
 * Create a thread for an ELF process with proper stack setup.
 */
create_elf_thread_internal :: proc(pid: u32, entry_point: u64, 
                                    stack_info: ^User_Stack_Info, 
                                    args: []string) -> *Thread {
    scheduler.lock.acquire()
    defer scheduler.lock.release()
    
    // Find free thread slot
    tid := find_free_thread_slot()
    if tid == 0 {
        return nil
    }
    
    thread := &scheduler.threads[tid]
    
    // Zero out thread
    mem.zero(mem.ptr(thread), size_of(Thread))
    
    // Initialize thread
    thread.tid = tid
    thread.pid = pid
    thread.state = .Ready
    thread.policy = .Round_Robin
    thread.priority = 0
    thread.nice = 0
    thread.remaining_quantum = SCHEDULER_QUANTUM_MS
    
    // Allocate kernel stack
    thread.kernel_stack_base = heap.alloc(KERNEL_STACK_SIZE)
    if thread.kernel_stack_base == nil {
        log.error("Scheduler: Failed to allocate kernel stack")
        return nil
    }
    
    thread.kernel_stack_top = cast(rawptr)(cast(uintptr)(thread.kernel_stack_base) + KERNEL_STACK_SIZE)
    
    // Set up initial context with user stack from ELF loading
    setup_elf_thread_context(thread, entry_point, stack_info, args)
    
    // Add to process's thread list (caller does this)
    
    // Add to runqueue
    add_to_runqueue(thread)
    
    scheduler.thread_count += 1
    
    log.debug("Scheduler: Created ELF thread TID=%d for PID=%d", tid, pid)
    
    return thread
}

create_thread_internal :: proc(pid: u32, entry_point: uintptr, user_mode: bool) -> *Thread {
    scheduler.lock.acquire()
    defer scheduler.lock.release()
    
    // Find free thread slot
    tid := find_free_thread_slot()
    if tid == 0 {
        return nil
    }
    
    thread := &scheduler.threads[tid]
    
    // Zero out thread
    mem.zero(mem.ptr(thread), size_of(Thread))
    
    // Initialize thread
    thread.tid = tid
    thread.pid = pid
    thread.state = .Ready
    thread.policy = .Round_Robin
    thread.priority = 0
    thread.nice = 0
    thread.remaining_quantum = SCHEDULER_QUANTUM_MS
    
    // Allocate kernel stack
    stack_size := KERNEL_STACK_SIZE
    if user_mode {
        stack_size = USER_STACK_SIZE
    }
    
    thread.kernel_stack_base = heap.alloc(stack_size)
    if thread.kernel_stack_base == nil {
        log.error("Scheduler: Failed to allocate kernel stack")
        return nil
    }
    
    thread.kernel_stack_top = cast(rawptr)(cast(uintptr)(thread.kernel_stack_base) + stack_size)
    
    // Set up initial context
    setup_thread_context(thread, entry_point, user_mode)
    
    // Add to process's thread list
    proc := &scheduler.processes[pid]
    proc.threads = append(proc.threads, thread)
    proc.thread_count += 1
    
    // Add to runqueue
    add_to_runqueue(thread)
    
    scheduler.thread_count += 1
    
    log.debug("Scheduler: Created thread TID=%d for PID=%d", tid, pid)
    
    return thread
}

find_free_thread_slot :: proc() -> u32 {
    for i in 1..<len(scheduler.threads) {
        if scheduler.threads[i].state == .Unused || 
           scheduler.threads[i].state == .Terminated {
            return u32(i)
        }
    }
    return 0
}

setup_thread_context :: proc(thread: *Thread, entry_point: uintptr, user_mode: bool) {
    ctx := &thread.context
    
    // Zero context
    mem.zero(mem.ptr(ctx), size_of(CPU_Context))
    
    // Set up stack
    ctx.rsp = cast(uintptr)(thread.kernel_stack_top)
    ctx.kernel_sp = ctx.rsp
    
    if user_mode {
        // User mode context
        ctx.cs = 0x1B  // User code segment
        ctx.ss = 0x23  // User stack segment
        ctx.rflags = 0x202  // IF flag set
        
        // Entry point
        ctx.rip = entry_point
        
        // User stack (would be allocated separately)
        // ctx.rsp = user_stack_top
    } else {
        // Kernel mode context
        ctx.cs = 0x08  // Kernel code segment
        ctx.ss = 0x10  // Kernel stack segment
        ctx.rflags = 0x202
        
        // Entry point
        ctx.rip = entry_point
    }
    
    // Set up base pointer
    ctx.rbp = 0
}

/**
 * Setup thread context for an ELF process with user stack.
 */
setup_elf_thread_context :: proc(thread: *Thread, entry_point: u64, 
                                  stack_info: ^User_Stack_Info, 
                                  args: []string) {
    ctx := &thread.context
    
    // Zero context
    mem.zero(mem.ptr(ctx), size_of(CPU_Context))
    
    // Set up kernel stack pointer (for when thread enters kernel mode)
    ctx.kernel_sp = cast(uintptr)(thread.kernel_stack_top)
    
    // Set up user mode context
    ctx.cs = 0x1B  // User code segment (ring 3)
    ctx.ss = 0x23  // User stack segment (ring 3)
    ctx.rflags = 0x202  // IF flag set, interrupts enabled
    
    // Set instruction pointer to ELF entry point
    ctx.rip = entry_point
    
    // Set user stack pointer (stack grows downward from top)
    ctx.rsp = stack_info.top
    
    // Base pointer initially zero
    ctx.rbp = 0
    
    // General purpose registers - can be used for ABI arguments
    // For System V AMD64 ABI:
    // RDI = argc
    // RSI = argv
    // RDX = envp
    // But we'll setup the stack properly instead
    
    log.debug("Scheduler: ELF thread context: RIP=0x%x, RSP=0x%x, KernelSP=0x%x", 
              ctx.rip, ctx.rsp, ctx.kernel_sp)
}

create_idle_thread :: proc() {
    // Idle thread runs at lowest priority
    thread := &scheduler.threads[0]
    
    mem.zero(mem.ptr(thread), size_of(Thread))
    
    thread.tid = 0
    thread.pid = 0
    thread.state = .Running
    thread.priority = -100  // Lowest possible
    thread.remaining_quantum = SCHEDULER_QUANTUM_MS
    
    // Minimal kernel stack
    thread.kernel_stack_base = heap.alloc(KERNEL_STACK_SIZE)
    thread.kernel_stack_top = cast(rawptr)(cast(uintptr)(thread.kernel_stack_base) + KERNEL_STACK_SIZE)
    
    // Idle function - just halt
    ctx := &thread.context
    mem.zero(mem.ptr(ctx), size_of(CPU_Context))
    ctx.rsp = cast(uintptr)(thread.kernel_stack_top)
    ctx.kernel_sp = ctx.rsp
    ctx.rip = cast(uintptr)(idle_loop)
    ctx.cs = 0x08
    ctx.ss = 0x10
    ctx.rflags = 0x202
    
    scheduler.idle_thread = thread
    scheduler.current_thread = thread
    
    log.debug("Scheduler: Idle thread created (TID=0)")
}

idle_loop :: proc() {
    for {
        cpu.halt()
    }
}

// ============================================================================
// Runqueue Management
// ============================================================================

add_to_runqueue :: proc(thread: *Thread) {
    cpu_id := 0  // TODO: Get actual CPU ID
    rq := &scheduler.runqueues[cpu_id]
    
    rq.lock.acquire()
    defer rq.lock.release()
    
    thread.state = .Ready
    thread.next = nil
    thread.prev = rq.tail
    
    if rq.tail != nil {
        rq.tail.next = thread
    } else {
        rq.head = thread
    }
    
    rq.tail = thread
    rq.count += 1
    
    log.debug("Scheduler: Added thread TID=%d to runqueue (count=%d)", thread.tid, rq.count)
}

remove_from_runqueue :: proc(thread: *Thread) {
    cpu_id := 0  // TODO: Get actual CPU ID
    rq := &scheduler.runqueues[cpu_id]
    
    rq.lock.acquire()
    defer rq.lock.release()
    
    if thread.prev != nil {
        thread.prev.next = thread.next
    } else {
        rq.head = thread.next
    }
    
    if thread.next != nil {
        thread.next.prev = thread.prev
    } else {
        rq.tail = thread.prev
    }
    
    thread.next = nil
    thread.prev = nil
    rq.count -= 1
}

get_next_thread :: proc() -> *Thread {
    cpu_id := 0  // TODO: Get actual CPU ID
    rq := &scheduler.runqueues[cpu_id]
    
    rq.lock.acquire()
    defer rq.lock.release()
    
    // Simple round-robin: take from head
    thread := rq.head
    if thread != nil {
        remove_from_runqueue(thread)
    }
    
    return thread
}

// ============================================================================
// Context Switching
// ============================================================================

// External function from arch.x86_64 package
extern switch_context: proc(old_ctx: *CPU_Context, new_ctx: *CPU_Context)

schedule :: proc() {
    if !scheduler.initialized {
        return
    }
    
    scheduler.lock.acquire()
    defer scheduler.lock.release()
    
    scheduler.schedule_calls += 1
    
    current := scheduler.current_thread
    if current == nil {
        current = scheduler.idle_thread
    }
    
    // Find next thread to run
    next := get_next_thread()
    
    // If no ready thread, run idle
    if next == nil {
        next = scheduler.idle_thread
    }
    
    // Don't switch if same thread
    if current == next {
        return
    }
    
    // Perform context switch
    do_context_switch(current, next)
}

do_context_switch :: proc(old_thread: *Thread, new_thread: *Thread) {
    // Save old thread state
    old_thread.state = .Ready
    
    // Update current thread
    scheduler.current_thread = new_thread
    new_thread.state = .Running
    
    scheduler.context_switches += 1
    
    log.debug("Scheduler: Context switch TID=%d -> TID=%d", old_thread.tid, new_thread.tid)
    
    // Perform actual context switch in assembly
    switch_context(&old_thread.context, &new_thread.context)
}

// ============================================================================
// Timer Tick Handler (Preemption)
// ============================================================================

timer_tick :: proc() {
    if !scheduler.initialized {
        return
    }
    
    scheduler.tick_count += 1
    scheduler.timer_ticks += 1
    
    current := scheduler.current_thread
    if current == nil || current == scheduler.idle_thread {
        return
    }
    
    // Decrement quantum
    current.remaining_quantum -= 1
    
    // Check if time slice expired
    if current.remaining_quantum <= 0 {
        // Re-add to runqueue
        add_to_runqueue(current)
        current.remaining_quantum = SCHEDULER_QUANTUM_MS
        
        // Trigger reschedule
        schedule()
    }
}

// ============================================================================
// Thread Blocking/Waking
// ============================================================================

block_thread :: proc(thread: *Thread, reason: rawptr) {
    if thread == nil {
        return
    }
    
    scheduler.lock.acquire()
    
    thread.state = .Blocked
    thread.blocked_on = reason
    
    // Remove from runqueue if it's there
    // (might not be if currently running)
    
    scheduler.lock.release()
}

wake_thread :: proc(thread: *Thread) {
    if thread == nil {
        return
    }
    
    scheduler.lock.acquire()
    
    if thread.state == .Blocked {
        thread.state = .Ready
        thread.blocked_on = nil
        add_to_runqueue(thread)
    }
    
    scheduler.lock.release()
}

sleep_thread :: proc(thread: *Thread, ticks: i64) {
    if thread == nil {
        return
    }
    
    scheduler.lock.acquire()
    
    thread.state = .Blocked
    thread.wake_time = scheduler.tick_count + ticks
    
    scheduler.lock.release()
}

check_sleeping_threads :: proc() {
    scheduler.lock.acquire()
    defer scheduler.lock.release()
    
    for i in 0..<scheduler.thread_count {
        thread := &scheduler.threads[i]
        if thread.state == .Blocked && thread.wake_time > 0 {
            if scheduler.tick_count >= thread.wake_time {
                thread.wake_time = 0
                wake_thread(thread)
            }
        }
    }
}

// ============================================================================
// Process/Thread Termination
// ============================================================================

exit_thread :: proc(thread: *Thread, exit_code: i32) {
    if thread == nil {
        return
    }
    
    scheduler.lock.acquire()
    
    thread.state = .Terminated
    thread.context.rip = 0
    
    // Free resources
    if thread.kernel_stack_base != nil {
        heap.free(thread.kernel_stack_base)
    }
    
    scheduler.lock.release()
    
    // Schedule to run another thread
    schedule()
}

exit_process :: proc(pid: u32, exit_code: i32) {
    if pid >= MAX_PROCESSES {
        return
    }
    
    scheduler.lock.acquire()
    
    proc := &scheduler.processes[pid]
    proc.state = .Zombie
    proc.exit_code = exit_code
    proc.exit_time = get_tick_count()
    
    // Terminate all threads
    for thread in proc.threads {
        if thread != nil {
            exit_thread(thread, exit_code)
        }
    }
    
    scheduler.lock.release()
    
    schedule()
}

// ============================================================================
// Query Functions
// ============================================================================

get_current_thread :: proc() -> *Thread {
    return scheduler.current_thread
}

get_current_pid :: proc() -> u32 {
    thread := get_current_thread()
    if thread != nil {
        return thread.pid
    }
    return 0
}

get_current_tid :: proc() -> u32 {
    thread := get_current_thread()
    if thread != nil {
        return thread.tid
    }
    return 0
}

get_tick_count :: proc() -> i64 {
    return scheduler.tick_count
}

get_process :: proc(pid: u32) -> *Process {
    if pid >= MAX_PROCESSES {
        return nil
    }
    return &scheduler.processes[pid]
}

get_thread :: proc(tid: u32) -> *Thread {
    if tid >= u32(len(scheduler.threads)) {
        return nil
    }
    return &scheduler.threads[tid]
}

// ============================================================================
// Debug/Statistics
// ============================================================================

print_scheduler_stats :: proc() {
    log.info("=== Scheduler Statistics ===")
    log.info("Context switches: %d", scheduler.context_switches)
    log.info("Schedule calls: %d", scheduler.schedule_calls)
    log.info("Timer ticks: %d", scheduler.timer_ticks)
    log.info("Total threads: %d", scheduler.thread_count)
    log.info("Total processes: %d", scheduler.process_count)
    log.info("Current thread: TID=%d", get_current_tid())
    log.info("===========================")
}

dump_runqueue :: proc() {
    cpu_id := 0
    rq := &scheduler.runqueues[cpu_id]
    
    log.info("=== Runqueue (CPU %d) ===", cpu_id)
    log.info("Count: %d", rq.count)
    
    thread := rq.head
    for thread != nil {
        log.info("  TID=%d, PID=%d, Priority=%d, State=%d", 
                thread.tid, thread.pid, thread.priority, thread.state)
        thread = thread.next
    }
    log.info("========================")
}
