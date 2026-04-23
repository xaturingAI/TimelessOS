; SYSCALL Entry Stub Implementation
; Handles transition from user mode (Ring 3) to kernel mode (Ring 0)

[BITS 64]

; External C/Odin functions
extern syscall_handler

; Save all registers and call syscall handler
global syscall_entry
syscall_entry:
    ; CPU automatically saves:
    ; - RIP to RCX
    ; - RFLAGS to R11
    
    ; Save user-mode RSP (will be restored on return)
    mov r12, rsp          ; Save user stack pointer temporarily
    
    ; Switch to kernel stack (TSS will handle this automatically via IST)
    ; But we need to save the user stack for later
    
    ; Push all general purpose registers (save state)
    push rax              ; Syscall number / return value placeholder
    push rbx
    push rcx              ; Saved RIP (from SYSCALL)
    push rdx              ; 4th argument
    push rsi              ; 3rd argument  
    push rdi              ; 2nd argument
    push rbp              ; Frame pointer
    push r8               ; 5th argument
    push r9               ; 6th argument
    push r10              ; 1st argument (SYSCALL uses R10 instead of RCX)
    push r11              ; Saved RFLAGS (from SYSCALL)
    push r12              ; Saved user RSP
    push r13
    push r14
    push r15
    
    ; Align stack to 16 bytes before call
    sub rsp, 8            ; Stack alignment
    
    ; Call the main syscall handler (Odin function)
    ; RDI = pointer to saved register frame
    mov rdi, rsp
    add rdi, 8            ; Point to first pushed register (RAX)
    call syscall_handler
    
    ; Restore stack alignment
    add rsp, 8
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12               ; Will use this for user RSP restoration
    pop r11               ; RFLAGS
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx               ; Will use this for RIP restoration
    pop rbx
    pop rax               ; Return value
    
    ; At this point:
    ; - RAX contains return value
    ; - RCX contains original RIP (user return address)
    ; - R11 contains original RFLAGS
    ; - R12 contains original user RSP
    
    ; Restore user stack pointer
    mov rsp, r12
    
    ; Return to user mode
    swapgs                ; Swap back to user GS base if using per-CPU data
    sysretq               ; Return from syscall (restores RIP from RCX, RFLAGS from R11)

; Alternative entry point for INT 0x80 (legacy compatibility)
global int80_entry
int80_entry:
    ; Interrupt pushes: SS, RSP, RFLAGS, CS, RIP, error code (if applicable)
    
    ; Save all registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Align stack
    sub rsp, 8
    
    ; Call handler
    mov rdi, rsp
    add rdi, 8
    call syscall_handler
    
    ; Restore stack
    add rsp, 8
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    ; Return from interrupt
    iretq
