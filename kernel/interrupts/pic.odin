// PIC (Programmable Interrupt Controller)
// Legacy 8259 PIC initialization and management

package interrupts.pic

import (
    "core:log"
    "arch:x86_64/io"
)

// PIC Ports
PIC1_COMMAND :: 0x20
PIC1_DATA ::   0x21
PIC2_COMMAND :: 0xA0
PIC2_DATA ::   0xA1

// PIC Commands
PIC_EOI :: 0x20  // End of Interrupt

// ICW4 Modes
ICW4_8086 :: 0x01
ICW4_AUTO :: 0x02

// Initialization Command Words
ICW1_ICW4 ::   0x01  // ICW4 present
ICW1_SINGLE :: 0x02  // Single mode
ICW1_INTERVAL4 :: 0x04  // Call address interval 4
ICW1_LEVEL ::  0x08  // Level triggered
ICW1_INIT ::   0x10  // Initialization

// PIC Masks
PIC_MASK_ALL :: 0xFF
PIC_MASK_NONE :: 0x00


// Initialize PIC
// Remaps IRQs to vectors 32-47 to avoid conflict with CPU exceptions (0-31)
init :: proc() {
    log.info("PIC: Initializing and remapping IRQs...")
    
    // Save masks
    mask1 := io.inb(PIC1_DATA)
    mask2 := io.inb(PIC2_DATA)
    
    // Start initialization sequence (ICW1)
    io.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4)
    io.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4)
    
    // Set vector offsets (ICW2)
    // PIC1 (master) -> vectors 32-39 (IRQ0-IRQ7)
    // PIC2 (slave)  -> vectors 40-47 (IRQ8-IRQ15)
    io.outb(PIC1_DATA, 32)   // Master offset
    io.outb(PIC2_DATA, 40)   // Slave offset
    
    // Set wiring (ICW3)
    // Tell master about slave (IRQ2)
    io.outb(PIC1_DATA, 0x04)  // Slave on IRQ2
    // Tell slave its cascade identity
    io.outb(PIC2_DATA, 0x02)  // Slave identity
    
    // Set 8086 mode (ICW4)
    io.outb(PIC1_DATA, ICW4_8086)
    io.outb(PIC2_DATA, ICW4_8086)
    
    // Restore masks
    io.outb(PIC1_DATA, mask1)
    io.outb(PIC2_DATA, mask2)
    
    log.info("PIC: Remapped IRQ0-IRQ15 to vectors 32-47")
}


// Enable IRQ Line
enable_irq :: proc(irq: u8) {
    if irq >= 16 {
        return
    }
    
    port := u16(PIC1_DATA)
    if irq >= 8 {
        port = PIC2_DATA
        irq -= 8
    }
    
    mask := io.inb(port)
    mask &= ~(1 << irq)
    io.outb(port, mask)
}


// Disable IRQ Line
disable_irq :: proc(irq: u8) {
    if irq >= 16 {
        return
    }
    
    port := u16(PIC1_DATA)
    if irq >= 8 {
        port = PIC2_DATA
        irq -= 8
    }
    
    mask := io.inb(port)
    mask |= (1 << irq)
    io.outb(port, mask)
}


// Send End of Interrupt
send_eoi :: proc(irq: u8) {
    if irq >= 8 {
        // Send EOI to slave
        io.outb(PIC2_COMMAND, PIC_EOI)
    }
    // Always send EOI to master
    io.outb(PIC1_COMMAND, PIC_EOI)
}


// Get IRQ Mask
get_mask :: proc() -> (master: u8, slave: u8) {
    return io.inb(PIC1_DATA), io.inb(PIC2_DATA)
}


// Set IRQ Mask
set_mask :: proc(master: u8, slave: u8) {
    io.outb(PIC1_DATA, master)
    io.outb(PIC2_DATA, slave)
}


// Disable PIC Completely
// Use when switching to APIC mode
disable :: proc() {
    log.info("PIC: Disabling...")
    io.outb(PIC1_DATA, PIC_MASK_ALL)
    io.outb(PIC2_DATA, PIC_MASK_ALL)
}


// Enable All IRQs
enable_all :: proc() {
    io.outb(PIC1_DATA, PIC_MASK_NONE)
    io.outb(PIC2_DATA, PIC_MASK_NONE)
}


// Check if IRQ is Pending
is_pending :: proc(irq: u8) -> bool {
    if irq >= 16 {
        return false
    }
    
    port := u16(PIC1_COMMAND)
    if irq >= 8 {
        port = PIC2_COMMAND
        irq -= 8
    }
    
    // Read ISR (In-Service Register)
    io.outb(port, 0x0B)  // OCW3: Read ISR
    isr := io.inb(port)
    
    return (isr & (1 << irq)) != 0
}
