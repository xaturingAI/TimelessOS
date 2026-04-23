// ISR Stub Implementations
// x86_64 assembly stubs for interrupt and exception handling
// These stubs save/restore registers and call the high-level handlers

package arch.x86_64

import (
    "core:intrinsics"
    "interrupts:idt"
    "interrupts:pic"
)

// ============================================================================
// Exception Handlers (Vectors 0-31)
// ============================================================================

// Divide Error (#DE) - Vector 0
// No error code pushed by CPU
isr_divide_error :: proc() {
    asm {
        // Push dummy error code (0) to maintain consistent stack frame
        push 0
        push 0  // vector number
        
        // Save all registers
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
        
        // Call the high-level handler
        mov rcx, rsp  // Pass pointer to interrupt frame
        call idt.exception_handler
        
        // Restore all registers
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
        
        // Remove vector and error code from stack
        add rsp, 16
        
        // Return from interrupt
        iretq
    }
}

// Debug Exception (#DB) - Vector 1
isr_debug_exception :: proc() {
    asm {
        push 0  // error code
        push 1  // vector number
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        
        mov rcx, rsp
        call idt.exception_handler
        
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Non-Maskable Interrupt (NMI) - Vector 2
isr_nmi :: proc() {
    asm {
        push 0  // error code
        push 2  // vector number
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        
        mov rcx, rsp
        call idt.exception_handler
        
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Breakpoint (#BP) - Vector 3
isr_breakpoint :: proc() {
    asm {
        push 0  // error code
        push 3  // vector number
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        
        mov rcx, rsp
        call idt.exception_handler
        
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Overflow (#OF) - Vector 4
isr_overflow :: proc() {
    asm {
        push 0; push 4
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Bound Range Exceeded (#BR) - Vector 5
isr_bound_range :: proc() {
    asm {
        push 0; push 5
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Invalid Opcode (#UD) - Vector 6
isr_invalid_opcode :: proc() {
    asm {
        push 0; push 6
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Device Not Available (#NM) - Vector 7
isr_device_not_available :: proc() {
    asm {
        push 0; push 7
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Double Fault (#DF) - Vector 8 (HAS ERROR CODE)
isr_double_fault :: proc() {
    asm {
        // Error code already on stack from CPU
        push 8  // vector number
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16  // Remove vector and error code
        iretq
    }
}

// Coprocessor Segment Overrun - Vector 9
isr_coprocessor_overrun :: proc() {
    asm {
        push 0; push 9
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Invalid TSS (#TS) - Vector 10 (HAS ERROR CODE)
isr_invalid_tss :: proc() {
    asm {
        push 10
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Segment Not Present (#NP) - Vector 11 (HAS ERROR CODE)
isr_segment_not_present :: proc() {
    asm {
        push 11
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Stack-Segment Fault (#SS) - Vector 12 (HAS ERROR CODE)
isr_stack_fault :: proc() {
    asm {
        push 12
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// General Protection Fault (#GP) - Vector 13 (HAS ERROR CODE)
isr_general_protection :: proc() {
    asm {
        push 13
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Page Fault (#PF) - Vector 14 (HAS ERROR CODE)
isr_page_fault :: proc() {
    asm {
        push 14
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Reserved - Vector 15
isr_reserved :: proc() {
    asm {
        push 0; push 15
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// x87 FPU Error (#MF) - Vector 16
isr_fpu_error :: proc() {
    asm {
        push 0; push 16
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Alignment Check (#AC) - Vector 17 (HAS ERROR CODE)
isr_alignment_check :: proc() {
    asm {
        push 17
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Machine Check (#MC) - Vector 18
isr_machine_check :: proc() {
    asm {
        push 0; push 18
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// SIMD FPU Exception (#XM) - Vector 19
isr_simd_exception :: proc() {
    asm {
        push 0; push 19
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Virtualization Exception (#VE) - Vector 20
isr_virtualization :: proc() {
    asm {
        push 0; push 20
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// Control Protection Exception (#CP) - Vector 21
isr_control_protection :: proc() {
    asm {
        push 0; push 21
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.exception_handler
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// ============================================================================
// Hardware IRQ Handlers (Vectors 32-47)
// ============================================================================

// IRQ0 - Timer (Vector 32)
// This is critical for scheduler preemption
isr_irq0 :: proc() {
    asm {
        push 0  // error code (placeholder)
        push 32 // vector number
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        
        // Call the high-level IRQ handler
        mov rcx, rsp
        call idt.irq_handler
        
        // Send EOI to PIC/APIC
        call pic.send_eoi_timer
        
        // Restore all registers
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ1 - Keyboard (Vector 33)
isr_irq1 :: proc() {
    asm {
        push 0; push 33
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ2 - Cascade (Vector 34)
isr_irq2 :: proc() {
    asm {
        push 0; push 34
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ3 - COM2 (Vector 35)
isr_irq3 :: proc() {
    asm {
        push 0; push 35
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ4 - COM1 (Vector 36)
isr_irq4 :: proc() {
    asm {
        push 0; push 36
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ5 - LPT2 (Vector 37)
isr_irq5 :: proc() {
    asm {
        push 0; push 37
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ6 - Floppy (Vector 38)
isr_irq6 :: proc() {
    asm {
        push 0; push 38
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ7 - LPT1 (Vector 39)
isr_irq7 :: proc() {
    asm {
        push 0; push 39
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ8 - RTC (Vector 40)
isr_irq8 :: proc() {
    asm {
        push 0; push 40
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ9 - Free/ACPI (Vector 41)
isr_irq9 :: proc() {
    asm {
        push 0; push 41
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ10 - Free/USB (Vector 42)
isr_irq10 :: proc() {
    asm {
        push 0; push 42
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ11 - Free (Vector 43)
isr_irq11 :: proc() {
    asm {
        push 0; push 43
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ12 - PS/2 Mouse (Vector 44)
isr_irq12 :: proc() {
    asm {
        push 0; push 44
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ13 - FPU (Vector 45)
isr_irq13 :: proc() {
    asm {
        push 0; push 45
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ14 - Primary ATA (Vector 46)
isr_irq14 :: proc() {
    asm {
        push 0; push 46
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// IRQ15 - Secondary ATA (Vector 47)
isr_irq15 :: proc() {
    asm {
        push 0; push 47
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        mov rcx, rsp
        call idt.irq_handler
        call pic.send_eoi
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}

// ============================================================================
// Syscall Handler (Legacy INT 0x80)
// ============================================================================

// Legacy Syscall Interface (Vector 128)
isr_syscall_legacy :: proc() {
    asm {
        push 0  // error code
        push 128 // vector number
        push rax; push rbx; push rcx; push rdx
        push rsi; push rdi; push rbp
        push r8; push r9; push r10; push r11
        push r12; push r13; push r14; push r15
        
        // Call syscall handler (to be implemented)
        mov rcx, rsp
        // call syscall.syscall_handler
        
        // For now, just return
        pop r15; pop r14; pop r13; pop r12
        pop r11; pop r10; pop r9; pop r8
        pop rbp; pop rdi; pop rsi
        pop rdx; pop rcx; pop rbx; pop rax
        add rsp, 16
        iretq
    }
}
