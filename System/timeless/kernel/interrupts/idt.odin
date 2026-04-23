// Interrupt Descriptor Table (IDT)
// Exception and interrupt handling

package interrupts.idt

import (
    "core:mem"
    "core:log"
    "arch:x86_64/cpu"
    "arch:x86_64"
    "mm:heap"
    "scheduler"
    "interrupts:pic"
)

// IDT Entry Count
IDT_ENTRIES :: 256


// IDT Gate Types
GATE_INTERRUPT :: 0x8E  // Interrupt gate (IF cleared)
GATE_TRAP ::     0x8F  // Trap gate (IF unchanged)
GATE_TASK ::     0x85  // Task gate


// IDT Entry Structure (16 bytes)
IDT_Entry :: struct {
    base_low:  u16,   // Bits 0-15 of ISR address
    selector:  u16,   // Kernel code segment selector
    ist:       u8,    // Interrupt Stack Table offset (0 = don't use)
    type_attr: u8,    // Gate type and attributes
    base_mid:  u16,   // Bits 16-31 of ISR address
    base_high: u32,   // Bits 32-63 of ISR address
    zero:      u32,   // Reserved
}


// IDT Structure
IDT :: struct {
    entries: [IDT_ENTRIES]IDT_Entry,
}


// IDT Pointer (for lidt instruction)
IDT_Ptr :: struct {
    limit: u16,
    base:  *IDT,
}


// Interrupt Stack Frame (pushed by CPU on interrupt)
Interrupt_Frame :: struct {
    // Pushed by CPU automatically
    rip:     u64,  // Instruction pointer
    cs:      u64,  // Code segment
    rflags:  u64,  // Flags
    rsp:     u64,  // Stack pointer (if privilege change)
    ss:      u64,  // Stack segment (if privilege change)
    
    // Pushed by our ISR stub (for hardware interrupts)
    vector:  u64,  // Interrupt vector number
    error:   u64,  // Error code (for some exceptions)
}


// Global IDT
idt: IDT
idt_ptr: IDT_Ptr


// Exception Names (for debugging)
exception_names: [32]string = {
    "#DE - Divide Error",
    "#DB - Debug Exception",
    "NMI - Non-Maskable Interrupt",
    "#BP - Breakpoint",
    "#OF - Overflow",
    "#BR - Bound Range Exceeded",
    "#UD - Invalid Opcode",
    "#NM - Device Not Available",
    "#DF - Double Fault",
    "Coprocessor Segment Overrun",
    "#TS - Invalid TSS",
    "#NP - Segment Not Present",
    "#SS - Stack-Segment Fault",
    "#GP - General Protection Fault",
    "#PF - Page Fault",
    "Reserved",
    "#MF - x87 FPU Error",
    "#AC - Alignment Check",
    "#MC - Machine Check",
    "#XM - SIMD FPU Exception",
    "#VE - Virtualization Exception",
    "#CP - Control Protection Exception",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "#SX - Security Exception",
    "Reserved",
}


// Initialize IDT
init :: proc() {
    log.info("IDT: Initializing...")
    
    // Zero out IDT
    mem.zero(mem.ptr(&idt), size_of(IDT))
    
    // Set up IDT pointer
    idt_ptr.limit = size_of(IDT) - 1
    idt_ptr.base = &idt
    
    // Remap PIC (before setting up entries)
    // This is done in interrupts.pic package
    
    // Set up exception handlers (vectors 0-31)
    setup_exception_handlers()
    
    // Set up hardware interrupt handlers (vectors 32-47)
    setup_irq_handlers()
    
    // Set up syscall/sysenter handlers (vector 0x80, 0x82)
    setup_syscall_handlers()
    
    // Load IDT
    load_idt()
    
    log.info("IDT: %d entries configured", IDT_ENTRIES)
}


// Set Up Exception Handlers
setup_exception_handlers :: proc() {
    // Exceptions 0-31 (CPU exceptions)
    // Each needs a specific handler because some push error codes
    
    // Divide Error (vector 0)
    set_gate(0, cast(uintptr)(isr_divide_error), GATE_INTERRUPT, 0)
    
    // Debug Exception (vector 1)
    set_gate(1, cast(uintptr)(isr_debug_exception), GATE_INTERRUPT, 0)
    
    // NMI (vector 2)
    set_gate(2, cast(uintptr)(isr_nmi), GATE_INTERRUPT, 0)
    
    // Breakpoint (vector 3)
    set_gate(3, cast(uintptr)(isr_breakpoint), GATE_TRAP, 0)
    
    // Overflow (vector 4)
    set_gate(4, cast(uintptr)(isr_overflow), GATE_INTERRUPT, 0)
    
    // Bound Range (vector 5)
    set_gate(5, cast(uintptr)(isr_bound_range), GATE_INTERRUPT, 0)
    
    // Invalid Opcode (vector 6)
    set_gate(6, cast(uintptr)(isr_invalid_opcode), GATE_INTERRUPT, 0)
    
    // Device Not Available (vector 7)
    set_gate(7, cast(uintptr)(isr_device_not_available), GATE_INTERRUPT, 0)
    
    // Double Fault (vector 8) - has error code
    set_gate(8, cast(uintptr)(isr_double_fault), GATE_INTERRUPT, 0)
    
    // Coprocessor Segment Overrun (vector 9)
    set_gate(9, cast(uintptr)(isr_coprocessor_overrun), GATE_INTERRUPT, 0)
    
    // Invalid TSS (vector 10) - has error code
    set_gate(10, cast(uintptr)(isr_invalid_tss), GATE_INTERRUPT, 0)
    
    // Segment Not Present (vector 11) - has error code
    set_gate(11, cast(uintptr)(isr_segment_not_present), GATE_INTERRUPT, 0)
    
    // Stack Fault (vector 12) - has error code
    set_gate(12, cast(uintptr)(isr_stack_fault), GATE_INTERRUPT, 0)
    
    // General Protection Fault (vector 13) - has error code
    set_gate(13, cast(uintptr)(isr_general_protection), GATE_INTERRUPT, 0)
    
    // Page Fault (vector 14) - has error code
    set_gate(14, cast(uintptr)(isr_page_fault), GATE_INTERRUPT, 0)
    
    // Reserved (vector 15)
    set_gate(15, cast(uintptr)(isr_reserved), GATE_INTERRUPT, 0)
    
    // x87 FPU Error (vector 16)
    set_gate(16, cast(uintptr)(isr_fpu_error), GATE_INTERRUPT, 0)
    
    // Alignment Check (vector 17) - has error code
    set_gate(17, cast(uintptr)(isr_alignment_check), GATE_INTERRUPT, 0)
    
    // Machine Check (vector 18)
    set_gate(18, cast(uintptr)(isr_machine_check), GATE_INTERRUPT, 0)
    
    // SIMD FPU Exception (vector 19)
    set_gate(19, cast(uintptr)(isr_simd_exception), GATE_INTERRUPT, 0)
    
    // Virtualization Exception (vector 20)
    set_gate(20, cast(uintptr)(isr_virtualization), GATE_INTERRUPT, 0)
    
    // Control Protection Exception (vector 21)
    set_gate(21, cast(uintptr)(isr_control_protection), GATE_INTERRUPT, 0)
    
    // Vectors 22-31 reserved
    for i in 22..<32 {
        set_gate(i, cast(uintptr)(isr_reserved), GATE_INTERRUPT, 0)
    }
}


// Set Up IRQ Handlers (Hardware Interrupts)
setup_irq_handlers :: proc() {
    // IRQ0-IRQ15 mapped to vectors 32-47 (after PIC remap)
    
    // IRQ0 - Timer
    set_gate(32, cast(uintptr)(isr_irq0), GATE_INTERRUPT, 0)
    
    // IRQ1 - Keyboard
    set_gate(33, cast(uintptr)(isr_irq1), GATE_INTERRUPT, 0)
    
    // IRQ2 - Cascade (used by PIC)
    set_gate(34, cast(uintptr)(isr_irq2), GATE_INTERRUPT, 0)
    
    // IRQ3 - COM2
    set_gate(35, cast(uintptr)(isr_irq3), GATE_INTERRUPT, 0)
    
    // IRQ4 - COM1
    set_gate(36, cast(uintptr)(isr_irq4), GATE_INTERRUPT, 0)
    
    // IRQ5 - LPT2
    set_gate(37, cast(uintptr)(isr_irq5), GATE_INTERRUPT, 0)
    
    // IRQ6 - Floppy
    set_gate(38, cast(uintptr)(isr_irq6), GATE_INTERRUPT, 0)
    
    // IRQ7 - LPT1
    set_gate(39, cast(uintptr)(isr_irq7), GATE_INTERRUPT, 0)
    
    // IRQ8 - RTC
    set_gate(40, cast(uintptr)(isr_irq8), GATE_INTERRUPT, 0)
    
    // IRQ9 - Free (ACPI, etc.)
    set_gate(41, cast(uintptr)(isr_irq9), GATE_INTERRUPT, 0)
    
    // IRQ10 - Free (USB, etc.)
    set_gate(42, cast(uintptr)(isr_irq10), GATE_INTERRUPT, 0)
    
    // IRQ11 - Free
    set_gate(43, cast(uintptr)(isr_irq11), GATE_INTERRUPT, 0)
    
    // IRQ12 - PS/2 Mouse
    set_gate(44, cast(uintptr)(isr_irq12), GATE_INTERRUPT, 0)
    
    // IRQ13 - FPU
    set_gate(45, cast(uintptr)(isr_irq13), GATE_INTERRUPT, 0)
    
    // IRQ14 - Primary ATA
    set_gate(46, cast(uintptr)(isr_irq14), GATE_INTERRUPT, 0)
    
    // IRQ15 - Secondary ATA
    set_gate(47, cast(uintptr)(isr_irq15), GATE_INTERRUPT, 0)
}


// Set Up Syscall Handlers
setup_syscall_handlers :: proc() {
    // Legacy INT 0x80 (vector 128)
    set_gate(128, cast(uintptr)(isr_syscall_legacy), GATE_TRAP, 3)  // DPL=3 for user access
    
    // SYSCALL/SYSRET (vector 0x82)
    // Configured via IA32_STAR, IA32_LSTAR MSRs in cpu package
}


// Set IDT Gate
set_gate :: proc(vector: u8, base: uintptr, type_attr: u8, dpl: u8) {
    entry := &idt.entries[vector]
    
    entry.base_low = u16(base & 0xFFFF)
    entry.selector = 0x08  // Kernel code segment
    entry.ist = 0
    entry.type_attr = type_attr | (dpl << 5)
    entry.base_mid = u16((base >> 16) & 0xFFFF)
    entry.base_high = u32((base >> 32) & 0xFFFFFFFF)
    entry.zero = 0
}


// Load IDT into CPU
load_idt :: proc() {
    asm {
        lidt [idt_ptr]
    }
}


// ISR Stub Declarations (implemented in arch/x86_64/isr_stubs.odin)
// These are the actual assembly implementations that save/restore registers

// Exception handlers (vectors 0-31) - defined in arch.x86_64.isr_stubs
extern isr_divide_error:      proc()
extern isr_debug_exception:   proc()
extern isr_nmi:               proc()
extern isr_breakpoint:        proc()
extern isr_overflow:          proc()
extern isr_bound_range:       proc()
extern isr_invalid_opcode:    proc()
extern isr_device_not_available: proc()
extern isr_double_fault:      proc()
extern isr_coprocessor_overrun: proc()
extern isr_invalid_tss:       proc()
extern isr_segment_not_present: proc()
extern isr_stack_fault:       proc()
extern isr_general_protection: proc()
extern isr_page_fault:        proc()
extern isr_reserved:          proc()
extern isr_fpu_error:         proc()
extern isr_alignment_check:   proc()
extern isr_machine_check:     proc()
extern isr_simd_exception:    proc()
extern isr_virtualization:    proc()
extern isr_control_protection: proc()

// Hardware IRQ handlers (vectors 32-47) - defined in arch.x86_64.isr_stubs
extern isr_irq0:  proc()  // Timer
extern isr_irq1:  proc()  // Keyboard
extern isr_irq2:  proc()
extern isr_irq3:  proc()
extern isr_irq4:  proc()
extern isr_irq5:  proc()
extern isr_irq6:  proc()
extern isr_irq7:  proc()
extern isr_irq8:  proc()
extern isr_irq9:  proc()
extern isr_irq10: proc()
extern isr_irq11: proc()
extern isr_irq12: proc()  // Mouse
extern isr_irq13: proc()
extern isr_irq14: proc()
extern isr_irq15: proc()

// Syscall handlers - defined in arch.x86_64.isr_stubs
extern isr_syscall_legacy: proc()


// Exception Handler (called from ISR stubs)
exception_handler :: proc(frame: *Interrupt_Frame) {
    vector := frame.vector
    
    if vector < 32 {
        log.error("CPU Exception %d: %s", vector, exception_names[vector])
        log.error("  RIP: 0x%p, RSP: 0x%p, RFLAGS: 0x%p", frame.rip, frame.rsp, frame.rflags)
        
        if vector == 14 {
            // Page fault - read CR2
            cr2 := cpu.read_cr2()
            log.error("  Page Fault Address: 0x%p", cr2)
            log.error("  Error Code: 0x%p", frame.error)
        }
        
        // Kernel panic on unhandled exception
        cpu.panic(exception_names[vector])
    }
}


// IRQ Handler (called from ISR stubs)
irq_handler :: proc(vector: u8, frame: *Interrupt_Frame) {
    irq := vector - 32
    
    // Handle specific IRQs
    switch irq {
    case 0:
        // Timer tick
        handle_timer_tick()
        
    case 1:
        // Keyboard
        handle_keyboard_irq()
        
    case 12:
        // Mouse
        handle_mouse_irq()
        
    case:
        // Spurious or unhandled
        log.debug("Spurious IRQ: %d", irq)
    }
    
    // Send EOI to PIC/APIC
    // Done in pic/apic packages
}


// Timer Tick Handler
handle_timer_tick :: proc() {
    // Update system time
    // Schedule tasks
    // Update timeouts
    
    // Call scheduler for preemption
    scheduler.timer_tick()
    
    // Check for sleeping threads to wake up
    scheduler.check_sleeping_threads()
}


// Keyboard IRQ Handler
handle_keyboard_irq :: proc() {
    // Read scancode from PS/2 controller
    // drivers.input.keyboard.handle_irq()
}


// Mouse IRQ Handler
handle_mouse_irq :: proc() {
    // Read mouse data from PS/2 controller
    // drivers.input.mouse.handle_irq()
}
