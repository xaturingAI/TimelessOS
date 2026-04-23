// APIC (Advanced Programmable Interrupt Controller)
// Local APIC and I/O APIC for multi-core interrupt handling

package interrupts.apic

import (
    "core:mem"
    "core:log"
    "core:intrinsics"
    "mm:virtual"
    "arch:x86_64/cpu"
)

// APIC Base Address
LOCAL_APIC_BASE :: 0xFEE0_0000

// APIC Register Offsets
APIC_ID ::      0x0020  // APIC ID
APIC_VER ::     0x0030  // APIC Version
APIC_TPR ::     0x0080  // Task Priority
APIC_APR ::     0x0090  // Arbitration Priority
APIC_PPR ::     0x00A0  // Processor Priority
APIC_EOI ::     0x00B0  // End of Interrupt
APIC_RRD ::     0x00C0  // Remote Read
APIC_LDR ::     0x00D0  // Logical Destination
APIC_DFR ::     0x00E0  // Destination Format
APIC_SV ::      0x00F0  // Spurious Interrupt
APIC_ISR ::     0x0100  // In-Service Register (8 registers)
APIC_TMR ::     0x0180  // Trigger Mode Register
APIC_IRR ::     0x0200  // Interrupt Request Register
APIC_ESR ::     0x0280  // Error Status
APIC_ICR_L ::   0x0300  // Interrupt Command (low)
APIC_ICR_H ::   0x0310  // Interrupt Command (high)
APIC_LVT_TMR :: 0x0320  // LVT Timer
APIC_LVT_TSR :: 0x0330  // LVT Thermal Sensor
APIC_LVT_PMR :: 0x0340  // LVT Performance Monitor
APIC_LVT_LINT0 :: 0x0350  // LVT LINT0
APIC_LVT_LINT1 :: 0x0360  // LVT LINT1
APIC_LVT_ERR :: 0x0370  // LVT Error
APIC_TMR_INIT :: 0x0380  // Timer Initial Count
APIC_TMR_CURR :: 0x0390  // Timer Current Count
APIC_TMR_DIV :: 0x03E0  // Timer Divide Configuration

// I/O APIC Base (will be detected from ACPI)
IO_APIC_BASE :: 0xFEC0_0000

// I/O APIC Registers
IO_APIC_ID ::   0x00
IO_APIC_VER ::  0x01
IO_APIC_ARB ::  0x02
IO_APIC_REDTBL :: 0x10  // Redirection Table Base

// Interrupt Delivery Modes
DELIVERY_FIXED ::    0x000
DELIVERY_LOWEST ::   0x100
DELIVERY_SMI ::      0x200
DELIVERY_NMI ::      0x400
DELIVERY_INIT ::     0x500
DELIVERY_STARTUP ::  0x600
DELIVERY_EXTINT ::   0x700

// Trigger Modes
TRIGGER_EDGE :: 0x0000
TRIGGER_LEVEL :: 0x4000

// Polarity
POLARITY_ACTIVE_HIGH :: 0x0000
POLARITY_ACTIVE_LOW :: 0x2000

// APIC Destination Modes
DEST_PHYSICAL :: 0x0000
DEST_LOGICAL :: 0x0800

// Spurious Interrupt Vector
SPURIOUS_VECTOR :: 0xFF


// APIC State
apic_enabled: bool = false
apic_base: uintptr = 0
apic_base_msr: u64 = 0
io_apic_present: bool = false
io_apic_version: u32 = 0
io_apic_redir_entries: int = 0
local_apic_id: u32 = 0
num_cpus: int = 1


// Initialize APIC
init :: proc() {
    log.info("APIC: Initializing...")
    
    // Check if APIC is supported
    if !cpu.has_feature(.APIC) {
        log.warn("APIC: Not supported by CPU, using PIC")
        return
    }
    
    // Read APIC base from MSR
    apic_base_msr = intrinsics.read_msr(0x1B)  // IA32_APIC_BASE
    
    if (apic_base_msr & (1 << 11)) == 0 {
        log.warn("APIC: Disabled by BIOS")
        return
    }
    
    apic_base = uintptr(apic_base_msr & 0xFFFF_F000)
    
    // Map APIC registers
    map_apic_registers()
    
    // Get local APIC ID
    local_apic_id = read_register(APIC_ID) >> 24
    
    log.info("APIC: Local APIC ID: %d", local_apic_id)
    log.info("APIC: Base address: 0x%p", apic_base)
    
    // Enable local APIC
    enable_local_apic()
    
    // Initialize I/O APIC
    init_io_apic()
    
    // Set up LVT entries
    setup_lvt()
    
    // Enable interrupts
    enable()
    
    apic_enabled = true
    log.info("APIC: Enabled")
}


// Map APIC Registers into Virtual Memory
map_apic_registers :: proc() {
    // Map 4KB for local APIC
    virt := virtual.allocate_kernel_virtual(4096)
    
    // Create identity mapping for APIC base
    // (In real implementation, use proper page table manipulation)
    virtual.map_page(virt, apic_base, 0x93)  // Present, Writable, Uncached
    
    // APIC registers are now accessible at 'virt'
    // Store mapping for later use
}


// Read APIC Register
read_register :: proc(offset: u32) -> u32 {
    ptr := cast(*volatile u32)(apic_base + offset)
    return ptr[]
}


// Write APIC Register
write_register :: proc(offset: u32, value: u32) {
    ptr := cast(*volatile u32)(apic_base + offset)
    ptr[] = value
}


// Enable Local APIC
enable_local_apic :: proc() {
    // Read spurious interrupt register
    svr := read_register(APIC_SV)
    
    // Enable APIC and set spurious vector
    svr |= (1 << 8)  // APIC Software Enable
    svr |= SPURIOUS_VECTOR
    
    write_register(APIC_SV, svr)
    
    // Clear error status
    write_register(APIC_ESR, 0)
    read_register(APIC_ESR)  // Read to clear
}


// Initialize I/O APIC
init_io_apic :: proc() {
    log.info("APIC: Initializing I/O APIC...")
    
    // Read I/O APIC version
    io_apic_version = io_apic_read(IO_APIC_VER)
    
    log.info("APIC: I/O APIC Version: 0x%08X", io_apic_version)
    
    // Extract max redirection entries
    io_apic_redir_entries = int((io_apic_version >> 16) & 0xFF) + 1
    
    log.info("APIC: I/O APIC Redirection Entries: %d", io_apic_redir_entries)
    
    io_apic_present = true
}


// Read I/O APIC Register
io_apic_read :: proc(reg: u32) -> u32 {
    // Select register
    io_port_write(IO_APIC_BASE, reg)
    
    // Read data
    return io_port_read(IO_APIC_BASE + 0x10)
}


// Write I/O APIC Register
io_apic_write :: proc(reg: u32, value: u32) {
    // Select register
    io_port_write(IO_APIC_BASE, reg)
    
    // Write data
    io_port_write(IO_APIC_BASE + 0x10, value)
}


// Set Up LVT (Local Vector Table)
setup_lvt :: proc() {
    // Mask all LVT entries initially
    write_register(APIC_LVT_TMR,  1 << 16)  // Timer - masked
    write_register(APIC_LVT_TSR,  1 << 16)  // Thermal
    write_register(APIC_LVT_PMR,  1 << 16)  // Performance
    write_register(APIC_LVT_LINT0, 1 << 16) // LINT0
    write_register(APIC_LVT_LINT1, 1 << 16) // LINT1
    write_register(APIC_LVT_ERR,  1 << 16)  // Error
    
    // Configure LINT0 as ExtINT (for legacy PIC compatibility)
    write_register(APIC_LVT_LINT0, DELIVERY_EXTINT | (1 << 15))  // Masked initially
    
    // Configure LINT1 as NMI
    write_register(APIC_LVT_LINT1, DELIVERY_NMI)
    
    // Configure timer (one-shot, masked initially)
    write_register(APIC_LVT_TMR, DELIVERY_FIXED | (1 << 16))
}


// Enable APIC Interrupts
enable :: proc() {
    // Enable interrupts in APIC
    // Clear task priority to allow all interrupts
    write_register(APIC_TPR, 0)
}


// Disable APIC
disable :: proc() {
    // Mask all LVT entries
    write_register(APIC_LVT_TMR,  1 << 16)
    write_register(APIC_LVT_TSR,  1 << 16)
    write_register(APIC_LVT_PMR,  1 << 16)
    write_register(APIC_LVT_LINT0, 1 << 16)
    write_register(APIC_LVT_LINT1, 1 << 16)
    write_register(APIC_LVT_ERR,  1 << 16)
    
    // Disable local APIC
    svr := read_register(APIC_SV)
    svr &= ~(1 << 8)  // Clear software enable bit
    write_register(APIC_SV, svr)
    
    apic_enabled = false
}


// Send End of Interrupt
send_eoi :: proc() {
    write_register(APIC_EOI, 0)
}


// Send IPI (Inter-Processor Interrupt)
send_ipi :: proc(apic_id: u32, vector: u8, delivery_mode: u32) {
    // Set destination in ICR high
    write_register(APIC_ICR_H, apic_id << 24)
    
    // Send IPI via ICR low
    icr_low := delivery_mode | u32(vector) | (1 << 14)  // Assert
    write_register(APIC_ICR_L, icr_low)
    
    // Wait for delivery status to clear
    for read_register(APIC_ICR_L) & (1 << 12) != 0 {
        // Busy wait
    }
}


// Send IPI to All Processors (excluding self)
send_ipi_all :: proc(vector: u8) {
    write_register(APIC_ICR_H, 0)
    write_register(APIC_ICR_L, DELIVERY_FIXED | u32(vector) | (1 << 14) | (1 << 3))
}


// Send IPI to All Including Self
send_ipi_all_self :: proc(vector: u8) {
    write_register(APIC_ICR_H, 0)
    write_register(APIC_ICR_L, DELIVERY_FIXED | u32(vector) | (1 << 14) | (1 << 2))
}


// Configure I/O APIC Interrupt
io_apic_configure_irq :: proc(irq: u8, vector: u8, apic_id: u32) {
    if !io_apic_present {
        return
    }
    
    if irq >= io_apic_redir_entries {
        return
    }
    
    // Calculate redirection table index
    reg_low := IO_APIC_REDTBL + irq * 2
    reg_high := reg_low + 1
    
    // Set up redirection entry
    entry_low := u32(vector) | DELIVERY_FIXED | TRIGGER_EDGE | POLARITY_ACTIVE_HIGH
    entry_high := apic_id << 24
    
    io_apic_write(reg_low, entry_low)
    io_apic_write(reg_high, entry_high)
}


// Mask I/O APIC Interrupt
io_apic_mask_irq :: proc(irq: u8) {
    if !io_apic_present {
        return
    }
    
    reg_low := IO_APIC_REDTBL + irq * 2
    entry := io_apic_read(reg_low)
    entry |= (1 << 16)  // Mask bit
    io_apic_write(reg_low, entry)
}


// Unmask I/O APIC Interrupt
io_apic_unmask_irq :: proc(irq: u8) {
    if !io_apic_present {
        return
    }
    
    reg_low := IO_APIC_REDTBL + irq * 2
    entry := io_apic_read(reg_low)
    entry &= ~(1 << 16)  // Clear mask bit
    io_apic_write(reg_low, entry)
}


// Get Local APIC ID
get_local_apic_id :: proc() -> u32 {
    return local_apic_id
}


// Check if APIC is Enabled
is_enabled :: proc() -> bool {
    return apic_enabled
}


// Helper: IO Port Write
io_port_write :: proc(port: u32, value: u32) {
    // Memory-mapped I/O for I/O APIC
    ptr := cast(*volatile u32)(IO_APIC_BASE)
    ptr[] = port
}


// Helper: IO Port Read
io_port_read :: proc(port: u32) -> u32 {
    ptr := cast(*volatile u32)(IO_APIC_BASE + 0x10)
    return ptr[]
}
