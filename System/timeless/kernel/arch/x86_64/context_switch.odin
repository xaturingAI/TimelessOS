// Context Switch Assembly Implementation
// x86_64 low-level context switching routines

package arch.x86_64

import (
    "core:intrinsics"
    "scheduler"
)

// Context Switch Implementation
// This is called from scheduler.do_context_switch
// Saves all necessary registers and switches stacks
switch_context :: proc(old_ctx: *scheduler.CPU_Context, new_ctx: *scheduler.CPU_Context) {
    // Disable interrupts during context switch
    intrinsics.cli()
    
    // Save old context - callee-saved registers
    old_ctx.rbx = save_rbx()
    old_ctx.rbp = save_rbp()
    old_ctx.r12 = save_r12()
    old_ctx.r13 = save_r13()
    old_ctx.r14 = save_r14()
    old_ctx.r15 = save_r15()
    
    // Save current stack pointer
    old_ctx.rsp = get_rsp()
    
    // Save FPU/SIMD state if available
    save_fp_state(&old_ctx.fp_state[0])
    
    // Load new stack pointer FIRST
    set_rsp(new_ctx.rsp)
    
    // Restore FPU/SIMD state
    restore_fp_state(&new_ctx.fp_state[0])
    
    // Restore callee-saved registers
    restore_rbx(new_ctx.rbx)
    restore_rbp(new_ctx.rbp)
    restore_r12(new_ctx.r12)
    restore_r13(new_ctx.r13)
    restore_r14(new_ctx.r14)
    restore_r15(new_ctx.r15)
    
    // Re-enable interrupts
    intrinsics.sti()
    
    // Return to the new context's instruction pointer
    // We do this by pushing the RIP onto the stack and returning
    return_to_rip(new_ctx.rip)
}

// Inline assembly helper functions

save_rbx :: proc() -> u64 {
    result: u64
    asm "mov %rbx, $0" :: [result] "=r" (result)
    return result
}

save_rbp :: proc() -> u64 {
    result: u64
    asm "mov %rbp, $0" :: [result] "=r" (result)
    return result
}

save_r12 :: proc() -> u64 {
    result: u64
    asm "mov %r12, $0" :: [result] "=r" (result)
    return result
}

save_r13 :: proc() -> u64 {
    result: u64
    asm "mov %r13, $0" :: [result] "=r" (result)
    return result
}

save_r14 :: proc() -> u64 {
    result: u64
    asm "mov %r14, $0" :: [result] "=r" (result)
    return result
}

save_r15 :: proc() -> u64 {
    result: u64
    asm "mov %r15, $0" :: [result] "=r" (result)
    return result
}

get_rsp :: proc() -> u64 {
    result: u64
    asm "mov %rsp, $0" :: [result] "=r" (result)
    return result
}

set_rsp :: proc(value: u64) {
    asm "mov $0, %rsp" :: "" (value)
}

restore_rbx :: proc(value: u64) {
    asm "mov $0, %rbx" :: "" (value)
}

restore_rbp :: proc(value: u64) {
    asm "mov $0, %rbp" :: "" (value)
}

restore_r12 :: proc(value: u64) {
    asm "mov $0, %r12" :: "" (value)
}

restore_r13 :: proc(value: u64) {
    asm "mov $0, %r13" :: "" (value)
}

restore_r14 :: proc(value: u64) {
    asm "mov $0, %r14" :: "" (value)
}

restore_r15 :: proc(value: u64) {
    asm "mov $0, %r15" :: "" (value)
}

save_fp_state :: proc(area: rawptr) {
    // Check if FXSAVE is supported (should be on all x86_64 CPUs)
    asm {
        fxsave [rcx]
    }
}

restore_fp_state :: proc(area: rawptr) {
    asm {
        fxrstor [rcx]
    }
}

return_to_rip :: proc(rip: u64) {
    // Push the target RIP onto the stack and return
    // This will cause the CPU to jump to the saved instruction pointer
    asm {
        mov rax, rip
        push rax
        ret
    }
}

// Thread start trampoline
// Called when a thread starts for the first time
// Sets up the stack frame and calls the actual entry point
thread_start_trampoline :: proc(entry_point: u64) {
    // Enable interrupts
    intrinsics.sti()
    
    // Call the thread entry point
    // The entry point should never return for user threads
    asm {
        mov rax, entry_point
        call rax
    }
    
    // If it does return, exit the thread
    scheduler.exit_thread(scheduler.get_current_thread(), 0)
}
