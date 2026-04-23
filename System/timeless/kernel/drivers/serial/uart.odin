// Serial UART Driver (16550A)
// Provides early debug console and serial I/O

package drivers.serial.uart

import (
    "core:log"
    "arch:x86_64/io"
    "arch:x86_64/cpu"
)

// COM Port Addresses
COM1_BASE :: 0x3F8
COM2_BASE :: 0x2F8
COM3_BASE :: 0x3E8
COM4_BASE :: 0x2E8

// UART Register Offsets
UART_RBR :: 0  // Receiver Buffer (read)
UART_THR :: 0  // Transmitter Holding (write)
UART_IER :: 1  // Interrupt Enable
UART_FCR :: 2  // FIFO Control (write)
UART_IIR :: 2  // Interrupt Identity (read)
UART_LCR :: 3  // Line Control
UART_MCR :: 4  // Modem Control
UART_LSR :: 5  // Line Status
UART_MSR :: 6  // Modem Status
UART_DLL :: 0  // Divisor Latch Low (when DLAB=1)
UART_DLM :: 1  // Divisor Latch High (when DLAB=1)

// Line Control Register
LCR_DLAB :: (1 << 7)  // Divisor Latch Access Bit
LCR_BREAK :: (1 << 6) // Set Break
LCR_STICK :: (1 << 5) // Stick Parity
LCR_EPAR :: (1 << 4)  // Even Parity
LCR_PARITY :: (1 << 3) // Parity Enable
LCR_STOP :: (1 << 2)  // Stop Bits (0=1, 1=2)
LCR_WLEN8 :: (1 << 0) | (1 << 1)  // 8-bit word length

// Line Status Register
LSR_DR ::   (1 << 0)  // Data Ready
LSR_OE ::   (1 << 1)  // Overrun Error
LSR_PE ::   (1 << 2)  // Parity Error
LSR_FE ::   (1 << 3)  // Framing Error
LSR_BI ::   (1 << 4)  // Break Interrupt
LSR_THRE :: (1 << 5)  // THR Empty
LSR_TEMT :: (1 << 6)  // TEMT Empty
LSR_ERROR :: (1 << 7) // FIFO Error

// FIFO Control Register
FCR_ENABLE :: (1 << 0)
FCR_CLEAR_RX :: (1 << 1)
FCR_CLEAR_TX :: (1 << 2)
FCR_DMA_MODE :: (1 << 3)

// Interrupt Enable Register
IER_RX_DATA :: (1 << 0)
IER_THR_EMPTY :: (1 << 1)
IER_RX_STATUS :: (1 << 2)
IER_MODEM :: (1 << 3)

// Default Configuration
DEFAULT_BAUD :: 115200
DEFAULT_PORT :: COM1_BASE

// Console state
console_initialized: bool = false
console_port: u16 = DEFAULT_PORT
console_lock: bool = false


// Initialize UART
init :: proc(port: u16 = DEFAULT_PORT, baud: u32 = DEFAULT_BAUD) {
    log.info("UART: Initializing COM%d at 0x%X", (port - COM1_BASE) / 0x100 + 1, port)
    
    // Disable interrupts
    io.outb(port + UART_IER, 0x00)
    
    // Enable DLAB (set baud rate divisor)
    io.outb(port + UART_LCR, io.inb(port + UART_LCR) | LCR_DLAB)
    
    // Set baud rate divisor
    divisor := 115200 / baud
    io.outb(port + UART_DLL, u8(divisor & 0xFF))
    io.outb(port + UART_DLM, u8((divisor >> 8) & 0xFF))
    
    // Disable DLAB, set 8N1
    io.outb(port + UART_LCR, LCR_WLEN8)
    
    // Enable FIFOs
    io.outb(port + UART_FCR, FCR_ENABLE | FCR_CLEAR_RX | FCR_CLEAR_TX)
    
    // Enable interrupts (optional, for interrupt-driven mode)
    // io.outb(port + UART_IER, IER_RX_DATA | IER_THR_EMPTY)
    
    log.info("UART: COM%d initialized at %d baud", (port - COM1_BASE) / 0x100 + 1, baud)
}


// Initialize Console (for early boot logging)
init_console :: proc() {
    init(COM1_BASE, DEFAULT_BAUD)
    console_initialized = true
    
    log.info("UART: Console initialized on COM1")
}


// Write a Single Byte
write_byte :: proc(byte: u8) {
    // Wait for THR to be empty
    while (io.inb(console_port + UART_LSR) & LSR_THRE) == 0 {
        cpu.pause()
    }
    
    io.outb(console_port + UART_THR, byte)
}


// Write a String
write :: proc(s: string) {
    if !console_initialized {
        return
    }
    
    for _, c in s {
        write_byte(u8(c))
        
        // Handle newline
        if c == '\n' {
            write_byte('\r')
        }
    }
}


// Write a String with Length
write_n :: proc(s: string, n: int) {
    if !console_initialized {
        return
    }
    
    count := 0
    for _, c in s {
        if count >= n {
            break
        }
        write_byte(u8(c))
        if c == '\n' {
            write_byte('\r')
        }
        count++
    }
}


// Read a Single Byte (blocking)
read_byte :: proc() -> u8 {
    // Wait for data ready
    while (io.inb(console_port + UART_LSR) & LSR_DR) == 0 {
        cpu.pause()
    }
    
    return io.inb(console_port + UART_RBR)
}


// Read a Byte (non-blocking)
try_read_byte :: proc() -> (u8, bool) {
    if (io.inb(console_port + UART_LSR) & LSR_DR) != 0 {
        return io.inb(console_port + UART_RBR), true
    }
    return 0, false
}


// Read a Line (blocking, up to max_len)
read_line :: proc(buffer: []u8, max_len: int) -> int {
    if !console_initialized {
        return 0
    }
    
    count := 0
    for count < max_len - 1 {
        c := read_byte()
        
        if c == '\r' || c == '\n' {
            if count > 0 {
                break
            }
            continue
        }
        
        if c == '\b' || c == 127 {  // Backspace
            if count > 0 {
                count--
                write("\b \b")
            }
            continue
        }
        
        if c >= 32 && c < 127 {  // Printable
            buffer[count] = c
            write_byte(c)
            count++
        }
    }
    
    buffer[count] = 0  // Null terminate
    write("\r\n")
    
    return count
}


// Check if Data Available
data_available :: proc() -> bool {
    return (io.inb(console_port + UART_LSR) & LSR_DR) != 0
}


// Check if Transmitter Empty
transmitter_empty :: proc() -> bool {
    return (io.inb(console_port + UART_LSR) & LSR_TEMT) != 0
}


// Set Baud Rate
set_baud :: proc(baud: u32) {
    divisor := 115200 / baud
    
    // Enable DLAB
    lcr := io.inb(console_port + UART_LCR)
    io.outb(console_port + UART_LCR, lcr | LCR_DLAB)
    
    // Set divisor
    io.outb(console_port + UART_DLL, u8(divisor & 0xFF))
    io.outb(console_port + UART_DLM, u8((divisor >> 8) & 0xFF))
    
    // Disable DLAB
    io.outb(console_port + UART_LCR, lcr & ~LCR_DLAB)
}


// Enable Interrupts
enable_interrupts :: proc() {
    io.outb(console_port + UART_IER, IER_RX_DATA | IER_THR_EMPTY)
}


// Disable Interrupts
disable_interrupts :: proc() {
    io.outb(console_port + UART_IER, 0x00)
}


// Handle UART Interrupt (called from IRQ handler)
handle_irq :: proc() -> bool {
    // Read IIR to determine interrupt cause
    iir := io.inb(console_port + UART_IIR)
    
    if (iir & 1) != 0 {
        return false  // No interrupt pending
    }
    
    interrupt_id := (iir >> 1) & 0x7
    
    switch interrupt_id {
    case 0x6:  // Timeout
        // FIFO mode timeout
        return true
        
    case 0x4:  // Received Data
        // Read data from RBR
        _ = io.inb(console_port + UART_RBR)
        return true
        
    case 0x2:  // THR Empty
        // Transmitter ready - can send more data
        return true
        
    case 0x3:  // Receiver Line Status
        // Read LSR to clear
        _ = io.inb(console_port + UART_LSR)
        return true
        
    case:
        return false
    }
}


// Get Port
get_port :: proc() -> u16 {
    return console_port
}


// Is Initialized
is_initialized :: proc() -> bool {
    return console_initialized
}
