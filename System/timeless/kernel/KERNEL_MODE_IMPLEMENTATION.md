# Kernel-Mode Implementation Summary

## Overview
This document summarizes the kernel-mode infrastructure added to TimelessOS for proper user/kernel mode transitions, system calls, and hardware privilege separation.

## Components Implemented

### 1. Task State Segment (TSS) - `/arch/x86_64/tss.odin`

**Purpose**: Hardware-enforced stack switching when transitioning from user mode (Ring 3) to kernel mode (Ring 0).

**Key Features**:
- `TSS` struct with IST (Interrupt Stack Table) entries
- `rsp0` field set to kernel stack top for automatic CPU stack switching
- `init_tss()` - Initializes TSS and loads TR register
- `update_kernel_stack()` - Updates RSP0 during context switches
- Hardware automatically switches to kernel stack on interrupts/syscalls from user mode

**Usage**:
```odin
cpu.init_tss(kernel_stack_top)
```

### 2. SYSCALL/SYSENTER Interface - `/arch/x86_64/syscall.odin`

**Purpose**: Fast system call mechanism for user→kernel transitions.

**MSRs Configured**:
- `IA32_LSTAR` (0xC0000082): Long mode syscall target address
- `IA32_STAR` (0xC0000081): Legacy syscall target and segment selectors
- `IA32_FMASK` (0xC0000084): Flags to mask during syscall

**Segment Selectors**:
- Kernel CS: 0x08 (Ring 0)
- User CS: 0x1B (Ring 3)
- Kernel SS: 0x10 (Ring 0)
- User SS: 0x23 (Ring 3)

**Functions**:
- `init_syscall()`: Configures all MSRs for SYSCALL instruction
- `init_sysenter()`: Configures SYSENTER for Intel compatibility
- `has_syscall()`, `has_sysenter()`: Feature detection

### 3. SYSCALL Entry Stub - `/arch/x86_64/syscall_stub.asm`

**Purpose**: Assembly entry point that saves user state and transitions to kernel handler.

**Key Operations**:
1. Saves all general-purpose registers (RAX-R15)
2. Preserves user stack pointer (RSP)
3. Aligns stack to 16 bytes
4. Calls Odin `syscall_handler()` function
5. Restores all registers
6. Executes `SYSRETQ` to return to user mode

**Register Convention**:
- R10: 1st syscall argument (SYSCALL uses R10 instead of RCX)
- RDI: 2nd argument
- RSI: 3rd argument
- RDX: 4th argument
- R8: 5th argument
- R9: 6th argument
- RAX: Syscall number / return value

**Entry Points**:
- `syscall_entry`: Main SYSCALL handler (fast path)
- `int80_entry`: Legacy INT 0x80 handler (compatibility)

### 4. System Call Handler - `/arch/x86_64/syscall_handler.odin`

**Purpose**: High-level syscall dispatch and implementation.

**Syscall Frame Structure**:
```odin
Syscall_Frame :: struct {
    r15, r14, r13, r12 : u64,
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
    rax : u64,  // Syscall number
}
```

**Implemented Syscalls**:
- `SYS_READ` (0): Read from file descriptor
- `SYS_WRITE` (1): Write to file descriptor
- `SYS_OPEN` (2): Open file
- `SYS_CLOSE` (3): Close file descriptor
- `SYS_EXIT` (60): Terminate process
- `SYS_GETPID` (39): Get process ID
- `SYS_YIELD` (100): Yield CPU to scheduler
- `SYS_GETTID` (186): Get thread ID

**Integration**:
- Calls `scheduler.exit_current_process()` on exit
- Calls `scheduler.yield_current()` on yield
- Returns -1 (ENOSYS) for unimplemented syscalls

### 5. Main Kernel Integration - `/main.odin`

**Changes Made**:
1. Added `cpu.init_syscall()` call after interrupt initialization
2. Added `cpu.init_tss()` with kernel stack pointer
3. Replaced idle loop with `scheduler.run()`
4. Added `create_first_user_process()` function

**Initialization Order**:
```
1. Early init
2. CPU features
3. Memory managers (physical, virtual, heap)
4. Interrupts (IDT, PIC, APIC)
5. Enable interrupts
6. Scheduler
7. Drivers (VGA, keyboard, mouse, GPU, network)
8. Filesystems (VFS, FAT32, ext4, XFS, ZFS)
9. Service manager (dinit)
10. **SYSCALL interface** ← NEW
11. **TSS** ← NEW
12. Create first user process ← NEW
13. Enter scheduler
```

## User↔Kernel Mode Transition Flow

### SYSCALL Path (Fast):
```
User Mode (Ring 3)
    ↓ SYSCALL instruction
    ↓ CPU: RIP→RCX, RFLAGS→R11
    ↓ CPU: Load kernel CS/SS
    ↓ CPU: Switch to TSS.RSP0 stack
    ↓ syscall_entry (assembly)
    ↓ Save all registers
    ↓ Call syscall_handler (Odin)
    ↓ Dispatch to specific syscall
    ↓ Execute kernel code
    ↓ Restore registers
    ↓ SYSRETQ instruction
    ↓ CPU: Restore user CS/SS, RSP, RIP, RFLAGS
User Mode (Ring 3)
```

### Interrupt Path (Hardware):
```
User Mode (Ring 3)
    ↓ Hardware interrupt
    ↓ CPU: Push SS, RSP, RFLAGS, CS, RIP
    ↓ CPU: Switch to TSS.RSP0 stack
    ↓ ISR stub (assembly)
    ↓ Save all registers
    ↓ Call interrupt handler
    ↓ Execute handler
    ↓ Restore registers
    ↓ IRETQ instruction
    ↓ CPU: Pop RIP, CS, RFLAGS, RSP, SS
User Mode (Ring 3)
```

## Context Switch Integration

The TSS is updated during every context switch:
```odin
// In scheduler/context_switch.odin
proc switch_to(next_thread: ^Thread) {
    // Update TSS with new kernel stack
    cpu.update_kernel_stack(next_thread.kernel_stack_top)
    
    // Perform actual context switch
    asm_context_switch(...)
}
```

This ensures that when an interrupt occurs while running a user process, the CPU automatically switches to that process's kernel stack.

## Security Considerations

1. **Stack Isolation**: User and kernel stacks are completely separate
2. **Privilege Levels**: User code runs at Ring 3, kernel at Ring 0
3. **Memory Protection**: Page tables mark kernel memory as supervisor-only
4. **Syscall Validation**: All syscall arguments must be validated before use
5. **Flag Masking**: FMASK prevents user from setting privileged flags

## Testing Checklist

- [ ] SYSCALL instruction executes without fault
- [ ] TSS stack switching works correctly
- [ ] Registers preserved across syscall
- [ ] Return values passed back to user space
- [ ] Interrupts from user mode switch to kernel stack
- [ ] SYSRETQ returns to correct user RIP/RSP
- [ ] Multiple processes can make syscalls concurrently
- [ ] Scheduler preemption works during user execution

## Future Work

1. **Binary Loader**: Implement ELF loader for actual user programs
2. **Memory Mapping**: Set up proper user page tables
3. **Copy From/To User**: Safe memory copy functions with validation
4. **Signal Handling**: Unix-style signal delivery
5. **Ptrace**: Debugging support
6. **32-bit Compatibility**: IA32 emulation for 32-bit binaries

## Files Created/Modified

| File | Status | Purpose |
|------|--------|---------|
| `/arch/x86_64/tss.odin` | Created | TSS management |
| `/arch/x86_64/syscall.odin` | Created | SYSCALL MSR setup |
| `/arch/x86_64/syscall_stub.asm` | Created | Assembly entry point |
| `/arch/x86_64/syscall_handler.odin` | Created | Syscall dispatch |
| `/main.odin` | Modified | Integration |

## Dependencies

- Scheduler module (for yield/exit)
- Heap manager (for stack allocation)
- Log module (for debugging)
- Core intrinsics (for MSR/CR access)
