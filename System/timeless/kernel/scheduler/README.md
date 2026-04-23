# Process Scheduler Implementation for TimelessOS

## Overview

This implementation adds a complete process scheduler to the TimelessOS kernel, addressing the critical missing component that was previously just a comment ("// Idle loop - scheduler takes over from here").

## Files Created/Modified

### New Files:

1. **`/workspace/System/timeless/kernel/scheduler/scheduler.odin`**
   - Core scheduler implementation
   - Process and thread management
   - Ready queue (runqueue) management
   - Context switching interface
   - Timer tick handling for preemption
   - Thread blocking/waking mechanisms

2. **`/workspace/System/timeless/kernel/arch/x86_64/context_switch.odin`**
   - Low-level context switch implementation
   - Register save/restore operations
   - FPU/SIMD state preservation (FXSAVE/FXRSTOR)
   - Stack switching
   - Thread start trampoline

### Modified Files:

3. **`/workspace/System/timeless/kernel/main.odin`**
   - Added scheduler import
   - Calls `scheduler.init()` after enabling interrupts
   - Replaced old `kernel_main_loop()` with scheduler-aware idle loop
   - Commented out placeholder for user-space init process creation

4. **`/workspace/System/timeless/kernel/interrupts/idt.odin`**
   - Added scheduler import
   - Modified `handle_timer_tick()` to call `scheduler.timer_tick()` for preemption
   - Added call to `scheduler.check_sleeping_threads()` to wake sleeping threads

## Key Features Implemented

### 1. Process Management
- **Process Control Block (PCB)**: Tracks process state, memory space, threads, resources
- **Process States**: Unused, Running, Ready, Blocked, Terminated, Zombie
- **Process Creation**: `scheduler.create_process()` creates new processes with memory space
- **Process Termination**: `scheduler.exit_process()` handles cleanup and zombie state

### 2. Thread Management
- **Thread Control Block (TCB)**: Complete register context, stack info, scheduling data
- **Thread States**: Unused, Running, Ready, Blocked, Terminated
- **Thread Creation**: `scheduler.create_thread()` for kernel and user-mode threads
- **Idle Thread**: Special thread (TID=0) that runs when nothing else is ready

### 3. Scheduling Algorithm
- **Round-Robin with Priority**: Default scheduling policy
- **Time Slicing**: Configurable quantum (default 10ms)
- **Priority Levels**: Range from -20 to +19 (higher = more important)
- **Nice Values**: Traditional Unix-style nice values (0-20)
- **Per-CPU Runqueues**: Support for SMP systems (currently configured for 1 CPU)

### 4. Context Switching
- **Full Register Save/Restore**: All general-purpose registers (RAX-R15)
- **FPU/SIMD State**: FXSAVE/FXRSTOR for floating-point and SIMD registers
- **Stack Switching**: Proper kernel/user stack management
- **Segment Selectors**: Correct CS/SS for kernel (0x08/0x10) and user mode (0x1B/0x23)

### 5. Preemption
- **Timer Tick Handler**: Called on every timer interrupt (IRQ0)
- **Quantum Decrement**: Remaining time slices decremented each tick
- **Automatic Reschedule**: When quantum expires, thread is requeued and reschedule triggered
- **Sleeping Threads**: Automatic wake-up of threads after specified ticks

### 6. Thread Synchronization
- **Blocking**: `scheduler.block_thread()` for waiting on resources
- **Waking**: `scheduler.wake_thread()` to make blocked threads ready
- **Sleep**: `scheduler.sleep_thread()` for timed delays
- **Spinlocks**: Used for protecting scheduler data structures

### 7. User-Kernel Mode Support
- **User Mode Threads**: Proper segment selectors and privilege levels
- **Kernel Mode Threads**: For internal kernel tasks
- **Memory Isolation**: Separate page directories per process
- **Stack Management**: Kernel stack (16KB) and user stack (8MB) allocation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     main.odin                                │
│  - Initializes scheduler after interrupts enabled           │
│  - Creates idle loop with scheduler integration             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  scheduler/scheduler.odin                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Scheduler State                                      │   │
│  │  - Process table (256 max)                           │   │
│  │  - Thread table (256K max)                           │   │
│  │  - Per-CPU runqueues                                 │   │
│  │  - Statistics                                        │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Process Management                                   │   │
│  │  - create_process()                                  │   │
│  │  - exit_process()                                    │   │
│  │  - get_process()                                     │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Thread Management                                    │   │
│  │  - create_thread()                                   │   │
│  │  - exit_thread()                                     │   │
│  │  - block_thread() / wake_thread()                    │   │
│  │  - sleep_thread()                                    │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Scheduling                                           │   │
│  │  - schedule() - main entry point                     │   │
│  │  - do_context_switch()                               │   │
│  │  - add_to_runqueue() / remove_from_runqueue()        │   │
│  │  - get_next_thread()                                 │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Timer Handling                                       │   │
│  │  - timer_tick() - called from IRQ0 handler          │   │
│  │  - check_sleeping_threads()                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│            arch/x86_64/context_switch.odin                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  switch_context()                                     │   │
│  │  1. Disable interrupts                               │   │
│  │  2. Save callee-saved registers (RBX,RBP,R12-R15)    │   │
│  │  3. Save stack pointer                               │   │
│  │  4. Save FPU/SIMD state (FXSAVE)                     │   │
│  │  5. Load new stack pointer                           │   │
│  │  6. Restore FPU/SIMD state (FXRSTOR)                 │   │
│  │  7. Restore registers                                │   │
│  │  8. Enable interrupts                                │   │
│  │  9. Return to new RIP                                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              interrupts/idt.odin                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  handle_timer_tick()                                  │   │
│  │  - Call scheduler.timer_tick()                       │   │
│  │  - Check sleeping threads                            │   │
│  │  - May trigger schedule() if quantum expired         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Data Structures

### CPU_Context (88 bytes + 512 bytes FPU)
```odin
CPU_Context :: struct {
    rax, rbx, rcx, rdx, rsi, rdi, rbp: u64
    r8, r9, r10, r11, r12, r13, r14, r15: u64
    rip, rflags, rsp: u64
    cs, ss: u64
    fp_state: [512]u8  // FXSAVE area
    kernel_sp: u64
}
```

### Thread (Variable size)
```odin
Thread :: struct {
    tid, pid: u32
    state: Thread_State
    policy: Sched_Policy
    priority, nice: i32
    context: CPU_Context
    kernel_stack_base, kernel_stack_top: rawptr
    user_stack_base: rawptr
    user_stack_size: usize
    remaining_quantum, total_runtime: i64
    blocked_on: rawptr
    wake_time: i64
    next, prev: *Thread  // For runqueue linking
}
```

### Process (Variable size)
```odin
Process :: struct {
    pid, ppid: u32
    state: Process_State
    name, cmd: string
    page_directory: virtual.Page_Directory
    threads: []*Thread
    thread_count: i32
    priority, nice: i32
    exit_code: i32
    // ... more fields
}
```

## Usage Example

```odin
// In kernel initialization
scheduler.init()

// Create a kernel thread
tid := scheduler.create_thread(cast(uintptr)(my_thread_func), false)

// Create a user process (when user-space loader is ready)
// pid := scheduler.create_process("init", entry_point, true)

// Block current thread waiting for resource
scheduler.block_thread(scheduler.get_current_thread(), &mutex)

// Wake up a thread
scheduler.wake_thread(thread)

// Sleep for 100 ticks
scheduler.sleep_thread(thread, 100)

// Get current thread info
current := scheduler.get_current_thread()
log.info("Running TID=%d, PID=%d", current.tid, current.pid)
```

## Integration Points

### With Memory Manager
- Allocates kernel stacks via `heap.alloc()`
- Creates page directories via `virtual.create_page_directory()`
- Frees resources on thread/process exit

### With Interrupt System
- Timer interrupt (IRQ0) triggers `scheduler.timer_tick()`
- Enables preemption when quantum expires
- Wakes sleeping threads periodically

### With User-Space
- Sets up proper segment selectors for user mode
- Manages user stack allocation
- Provides isolation via separate page directories
- Will integrate with syscall interface (TODO)

## Future Enhancements

1. **Multi-Processor Support**: Full SMP with per-CPU runqueues and load balancing
2. **Advanced Scheduling**: 
   - Completely Fair Scheduler (CFS)
   - Real-time scheduling classes
   - CPU affinity and pinning
3. **Inter-Process Communication**: Pipes, message queues, shared memory
4. **Synchronization Primitives**: Mutexes, semaphores, condition variables
5. **Signals**: Unix-style signal delivery and handling
6. **Process Groups and Sessions**: Job control support
7. **Resource Limits**: ulimit-style constraints
8. **Profiling and Debugging**: Performance counters, tracing

## Testing Recommendations

1. **Context Switch Correctness**: Verify all registers are saved/restored
2. **Preemption**: Ensure timer interrupts cause reschedule
3. **Priority**: Higher priority threads should run first
4. **Fairness**: Round-robin should be fair among equal-priority threads
5. **Blocking/Waking**: Test various synchronization scenarios
6. **Stress Testing**: Many threads competing for CPU
7. **Memory Leaks**: Verify stacks are freed on exit

## Notes

- The scheduler uses a simple round-robin algorithm initially
- Lock ordering: Always acquire scheduler.lock before runqueue locks
- Interrupts are disabled during context switches
- The idle thread (TID=0) is special and never blocks
- User-mode support is implemented but requires user-space loader integration
