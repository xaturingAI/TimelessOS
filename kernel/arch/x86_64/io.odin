// x86_64 I/O Port Operations
// Low-level port I/O for device communication

package arch.x86_64.io

import (
    "core:intrinsics"
)

// Read Byte from Port
inb :: proc(port: u16) -> u8 {
    result: u8
    asm {
        mov dx, port
        in al, dx
        mov result, al
    }
    return result
}


// Read Word from Port
inw :: proc(port: u16) -> u16 {
    result: u16
    asm {
        mov dx, port
        in ax, dx
        mov result, ax
    }
    return result
}


// Read Doubleword from Port
inl :: proc(port: u16) -> u32 {
    result: u32
    asm {
        mov dx, port
        in eax, dx
        mov result, eax
    }
    return result
}


// Write Byte to Port
outb :: proc(port: u16, value: u8) {
    asm {
        mov dx, port
        mov al, value
        out dx, al
    }
}


// Write Word to Port
outw :: proc(port: u16, value: u16) {
    asm {
        mov dx, port
        mov ax, value
        out dx, ax
    }
}


// Write Doubleword to Port
outl :: proc(port: u16, value: u32) {
    asm {
        mov dx, port
        mov eax, value
        out dx, eax
    }
}


// Read Multiple Bytes (string I/O)
insb :: proc(port: u16, buffer: []u8) {
    asm {
        mov dx, port
        mov rdi, &buffer[0]
        mov rcx, len(buffer)
        rep insb
    }
}


// Write Multiple Bytes (string I/O)
outsb :: proc(port: u16, buffer: []u8) {
    asm {
        mov dx, port
        mov rsi, &buffer[0]
        mov rcx, len(buffer)
        rep outsb
    }
}


// Read Multiple Words
insw :: proc(port: u16, buffer: []u16) {
    asm {
        mov dx, port
        mov rdi, &buffer[0]
        mov rcx, len(buffer)
        rep insw
    }
}


// Write Multiple Words
outsw :: proc(port: u16, buffer: []u16) {
    asm {
        mov dx, port
        mov rsi, &buffer[0]
        mov rcx, len(buffer)
        rep outsw
    }
}


// I/O Wait (delay)
io_wait :: proc() {
    // Write to unused port 0x80 to cause I/O delay
    outb(0x80, 0)
}


// Delay in microseconds (approximate)
delay_us :: proc(us: u32) {
    // Rough approximation using TSC
    // Assumes ~2-3 GHz CPU
    start := intrinsics.read_tsc()
    target := start + u64(us) * 2000  // ~2 cycles per ns
    
    while intrinsics.read_tsc() < target {
        intrinsics.pause()
    }
}


// Delay in milliseconds
delay_ms :: proc(ms: u32) {
    for _ in 0..<ms {
        delay_us(1000)
    }
}
