// VGA Text Mode Driver
// 80x25 text mode console

package drivers.video.vga

import (
    "core:mem"
    "core:log"
    "core:fmt"
    "mm:virtual"
)

// VGA Text Mode Constants
VGA_BUFFER :: 0xB8000
VGA_WIDTH :: 80
VGA_HEIGHT :: 25
VGA_CELLS :: VGA_WIDTH * VGA_HEIGHT

// VGA Colors
Color :: enum {
    Black,
    Blue,
    Green,
    Cyan,
    Red,
    Magenta,
    Brown,
    Light_Gray,
    Dark_Gray,
    Light_Blue,
    Light_Green,
    Light_Cyan,
    Light_Red,
    Light_Magenta,
    Yellow,
    White,
}

// Default Colors
DEFAULT_FG :: Color.Light_Gray
DEFAULT_BG :: Color.Black

// VGA Entry Structure
VGA_Entry :: u16

// VGA State
vga_buffer: *VGA_Buffer
cursor_x: int = 0
cursor_y: int = 0
color: u8 = make_color(DEFAULT_FG, DEFAULT_BG)
scroll_offset: int = 0


// VGA Buffer
VGA_Buffer :: struct {
    cells: [VGA_CELLS]VGA_Entry,
}


// Initialize VGA Text Mode
init :: proc() {
    log.info("VGA: Initializing text mode...")
    
    // Map VGA buffer into kernel virtual address space
    // Physical 0xB8000 -> Virtual address
    vga_phys := uintptr(VGA_BUFFER)
    vga_virt := virtual.physical_to_virtual(vga_phys)
    
    vga_buffer = cast(*VGA_Buffer)(vga_virt)
    
    // Clear screen
    clear()
    
    // Set cursor to top-left
    set_cursor(0, 0)
    
    log.info("VGA: Text mode initialized (80x25)")
}


// Make Color Byte
make_color :: proc(fg: Color, bg: Color) -> u8 {
    return (u8(bg) << 4) | u8(fg)
}


// Create VGA Entry
make_entry :: proc(c: u8, color: u8) -> VGA_Entry {
    return (u16(color) << 8) | u16(c)
}


// Clear Screen
clear :: proc() {
    blank := make_entry(' ', color)
    for i in 0..<VGA_CELLS {
        vga_buffer.cells[i] = blank
    }
    cursor_x = 0
    cursor_y = 0
    scroll_offset = 0
    update_cursor()
}


// Set Cursor Position
set_cursor :: proc(x: int, y: int) {
    cursor_x = x
    cursor_y = y
    update_cursor()
}


// Get Cursor Position
get_cursor :: proc() -> (x: int, y: int) {
    return cursor_x, cursor_y
}


// Update Hardware Cursor
update_cursor :: proc() {
    position := cursor_y * VGA_WIDTH + cursor_x
    
    // VGA controller ports
    VGA_CTRL :: 0x3D4
    VGA_DATA :: 0x3D5
    
    // Send high byte
    asm {
        mov dx, VGA_CTRL
        mov al, 14
        out dx, al
        mov dx, VGA_DATA
        mov ax, position
        shr ax, 8
        out dx, al
    }
    
    // Send low byte
    asm {
        mov dx, VGA_CTRL
        mov al, 15
        out dx, al
        mov dx, VGA_DATA
        mov ax, position
        out dx, al
    }
}


// Write a Character
put_char :: proc(c: u8) {
    if c == '\n' {
        cursor_x = 0
        cursor_y++
    } else if c == '\r' {
        cursor_x = 0
    } else if c == '\t' {
        cursor_x = (cursor_x + 8) & ~7
    } else if c == '\b' {
        if cursor_x > 0 {
            cursor_x--
            idx := cursor_y * VGA_WIDTH + cursor_x
            vga_buffer.cells[idx] = make_entry(' ', color)
        }
    } else if c >= 32 && c < 127 {
        idx := cursor_y * VGA_WIDTH + cursor_x
        vga_buffer.cells[idx] = make_entry(c, color)
        cursor_x++
    }
    
    // Check for line wrap
    if cursor_x >= VGA_WIDTH {
        cursor_x = 0
        cursor_y++
    }
    
    // Check for scroll
    if cursor_y >= VGA_HEIGHT {
        scroll()
        cursor_y = VGA_HEIGHT - 1
    }
    
    update_cursor()
}


// Write a String
write :: proc(s: string) {
    for _, c in s {
        put_char(u8(c))
    }
}


// Write Formatted String
printf :: proc(format: string, args: ..any) {
    s := fmt.sprintf(format, args)
    write(s)
}


// Scroll Screen Up
scroll :: proc() {
    scroll_offset++
    
    // Move all lines up by one
    for y in 0..<VGA_HEIGHT - 1 {
        for x in 0..<VGA_WIDTH {
            src := (y + 1) * VGA_WIDTH + x
            dst := y * VGA_WIDTH + x
            vga_buffer.cells[dst] = vga_buffer.cells[src]
        }
    }
    
    // Clear bottom line
    blank := make_entry(' ', color)
    for x in 0..<VGA_WIDTH {
        vga_buffer.cells[(VGA_HEIGHT - 1) * VGA_WIDTH + x] = blank
    }
}


// Set Text Color
set_color :: proc(fg: Color, bg: Color) {
    color = make_color(fg, bg)
}


// Get Text Color
get_color :: proc() -> (fg: Color, bg: Color) {
    fg = Color(color & 0x0F)
    bg = Color((color >> 4) & 0x0F)
    return
}


// Write Character at Position
put_char_at :: proc(x: int, y: int, c: u8) {
    if x < 0 || x >= VGA_WIDTH || y < 0 || y >= VGA_HEIGHT {
        return
    }
    idx := y * VGA_WIDTH + x
    vga_buffer.cells[idx] = make_entry(c, color)
}


// Write String at Position
write_at :: proc(x: int, y: int, s: string) {
    old_x := cursor_x
    old_y := cursor_y
    set_cursor(x, y)
    write(s)
    set_cursor(old_x, old_y)
}


// Display Kernel Panic Screen
display_panic :: proc(message: string, location: runtime.Source_Location) {
    // Disable cursor
    asm {
        mov dx, 0x3D4
        mov al, 10
        out dx, al
        mov dx, 0x3D5
        mov al, 0x20
        out dx, al
    }
    
    // Red background, white text
    set_color(.White, .Red)
    clear()
    
    // Panic header
    write_at(0, 0, "========================================")
    write_at(0, 1, "       TIMELESSOS KERNEL PANIC          ")
    write_at(0, 2, "========================================")
    
    // Error location
    printf(3, 4, "Location: %s:%d", location.file, location.line)
    
    // Error message
    printf(3, 6, "Error: %s", message)
    
    // System info
    write_at(3, 8, "System halted. Please restart.")
    
    // Infinite loop
    for {
        asm { hlt }
    }
}


// Draw Box
draw_box :: proc(x1: int, y1: int, x2: int, y2: int) {
    // Top and bottom
    for x in x1..=x2 {
        put_char_at(x, y1, '-')
        put_char_at(x, y2, '-')
    }
    // Left and right
    for y in y1..=y2 {
        put_char_at(x1, y, '|')
        put_char_at(x2, y, '|')
    }
    // Corners
    put_char_at(x1, y1, '+')
    put_char_at(x2, y1, '+')
    put_char_at(x1, y2, '+')
    put_char_at(x2, y2, '+')
}


// Fill Rectangle
fill_rect :: proc(x1: int, y1: int, x2: int, y2: int, c: u8) {
    for y in y1..=y2 {
        for x in x1..=x2 {
            put_char_at(x, y, c)
        }
    }
}


// Get Buffer Pointer
get_buffer :: proc() -> *VGA_Buffer {
    return vga_buffer
}


// Get Width
get_width :: proc() -> int {
    return VGA_WIDTH
}


// Get Height
get_height :: proc() -> int {
    return VGA_HEIGHT
}
