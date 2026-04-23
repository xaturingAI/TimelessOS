// PS/2 Mouse Driver
// Handles mouse input via PS/2 controller

package drivers.input.mouse

import (
    "core:log"
    "arch:x86_64/io"
    "interrupts:pic"
)

// PS/2 Mouse Commands
MOUSE_ENABLE_DATA_REPORTING :: 0xF4
MOUSE_DISABLE_DATA_REPORTING :: 0xF5
MOUSE_SET_DEFAULTS :: 0xF6
MOUSE_SET_SAMPLE_RATE :: 0xF3
MOUSE_SET_RESOLUTION :: 0xE8
MOUSE_GET_ID :: 0xF2
MOUSE_RESET :: 0xFF

// Mouse Packet Bits
MOUSE_PACKET_SIZE :: 3
MOUSE_Y_OVERFLOW :: (1 << 6)
MOUSE_X_OVERFLOW :: (1 << 5)
MOUSE_Y_SIGN ::     (1 << 4)
MOUSE_X_SIGN ::     (1 << 3)
MOUSE_ALWAYS_1 ::   (1 << 3)
MOUSE_MIDDLE ::     (1 << 2)
MOUSE_RIGHT ::      (1 << 1)
MOUSE_LEFT ::       (1 << 0)

// Mouse State
mouse_initialized: bool = false
mouse_present: bool = false
mouse_type: int = 0  // 0 = none, 1 = standard, 2 = IntelliMouse (wheel)
mouse_x: int = 0
mouse_y: int = 0
mouse_z: int = 0  // Wheel
mouse_buttons: u8 = 0
mouse_sample_rate: u8 = 100
mouse_resolution: u8 = 3  // 4 counts/mm

// Mouse Event Handler
Mouse_Event_Handler :: proc(x: int, y: int, z: int, buttons: u8)

event_handler: Mouse_Event_Handler = nil


// Initialize Mouse
init :: proc() {
    log.info("Mouse: Initializing PS/2 mouse...")
    
    // Enable auxiliary device (mouse) port
    enable_auxiliary_device()
    
    // Reset mouse
    if !reset_mouse() {
        log.warn("Mouse: Reset failed, continuing anyway")
    }
    
    // Set sample rate
    set_sample_rate(100)
    
    // Set resolution
    set_resolution(3)
    
    // Enable data reporting
    enable_data_reporting()
    
    // Detect mouse type
    detect_mouse_type()
    
    mouse_initialized = true
    
    log.info("Mouse: PS/2 mouse initialized (type: %d)", mouse_type)
}


// Enable Auxiliary Device
enable_auxiliary_device :: proc() {
    // Wait for controller
    wait_controller()
    
    // Enable auxiliary device
    io.outb(0x64, 0xA8)
}


// Wait for Controller
wait_controller :: proc() {
    timeout := 100000
    for timeout > 0 {
        status := io.inb(0x64)
        if (status & 0x02) == 0 {
            return
        }
        timeout--
    }
}


// Wait for Mouse Data
wait_mouse_data :: proc() -> u8 {
    timeout := 100000
    while timeout > 0 {
        status := io.inb(0x64)
        if (status & 0x01) != 0 {
            return io.inb(0x60)
        }
        timeout--
    }
    return 0
}


// Send Command to Mouse
send_mouse_command :: proc(cmd: u8) -> bool {
    // Send "write to auxiliary device" command
    wait_controller()
    io.outb(0x64, 0xD4)
    
    // Wait then send command
    wait_controller()
    io.outb(0x60, cmd)
    
    // Wait for ACK
    response := wait_mouse_data()
    if response == 0xFA {
        return true
    }
    return false
}


// Reset Mouse
reset_mouse :: proc() -> bool {
    wait_controller()
    io.outb(0x64, 0xD4)
    wait_controller()
    io.outb(0x60, MOUSE_RESET)
    
    // Wait for ACK
    response := wait_mouse_data()
    if response != 0xFA {
        return false
    }
    
    // Wait for completion code
    response = wait_mouse_data()
    if response == 0x00 {
        mouse_type = 1
        return true
    } else if response == 0x03 {
        mouse_type = 2  // IntelliMouse
        return true
    }
    
    return false
}


// Set Sample Rate
set_sample_rate :: proc(rate: u8) -> bool {
    if !send_mouse_command(MOUSE_SET_SAMPLE_RATE) {
        return false
    }
    wait_controller()
    io.outb(0x60, rate)
    _ = wait_mouse_data()  // ACK
    mouse_sample_rate = rate
    return true
}


// Set Resolution
set_resolution :: proc(resolution: u8) -> bool {
    if !send_mouse_command(MOUSE_SET_RESOLUTION) {
        return false
    }
    wait_controller()
    io.outb(0x60, resolution)
    _ = wait_mouse_data()  // ACK
    mouse_resolution = resolution
    return true
}


// Enable Data Reporting
enable_data_reporting :: proc() -> bool {
    return send_mouse_command(MOUSE_ENABLE_DATA_REPORTING)
}


// Disable Data Reporting
disable_data_reporting :: proc() -> bool {
    return send_mouse_command(MOUSE_DISABLE_DATA_REPORTING)
}


// Detect Mouse Type
detect_mouse_type :: proc() {
    // Try IntelliMouse detection sequence
    // Sequence: 200, 100, 80 sample rates
    
    set_sample_rate(200)
    set_sample_rate(100)
    set_sample_rate(80)
    
    // Get device ID
    send_mouse_command(MOUSE_GET_ID)
    mouse_id := wait_mouse_data()
    
    if mouse_id == 0x03 {
        mouse_type = 2  // IntelliMouse with wheel
        log.info("Mouse: IntelliMouse detected (wheel support)")
    } else {
        mouse_type = 1  // Standard mouse
        log.info("Mouse: Standard PS/2 mouse detected")
    }
    
    // Set back to normal reporting
    set_sample_rate(100)
    enable_data_reporting()
}


// Handle Mouse IRQ (IRQ12 -> vector 44)
handle_irq :: proc() {
    if !mouse_initialized {
        return
    }
    
    // Read mouse packet
    packet := [MOUSE_PACKET_SIZE]u8{0, 0, 0}
    
    // Read byte 0 (status)
    packet[0] = io.inb(0x60)
    
    // Read remaining bytes
    for i in 1..<MOUSE_PACKET_SIZE {
        packet[i] = io.inb(0x60)
    }
    
    // Parse packet
    parse_packet(packet)
}


// Parse Mouse Packet
parse_packet :: proc(packet: [3]u8) {
    // Check if packet is valid (bit 3 should always be 1)
    if (packet[0] & MOUSE_ALWAYS_1) == 0 {
        log.warn("Mouse: Invalid packet (sync error)")
        return
    }
    
    // Button state
    mouse_buttons = packet[0] & 0x07
    
    // X movement
    x := i16(packet[1])
    if (packet[0] & MOUSE_X_SIGN) != 0 {
        x |= 0xFF00  // Sign extend
    }
    
    // Y movement
    y := i16(packet[2])
    if (packet[0] & MOUSE_Y_SIGN) != 0 {
        y |= 0xFF00  // Sign extend
    }
    
    // Check for overflow
    if (packet[0] & MOUSE_X_OVERFLOW) != 0 || (packet[0] & MOUSE_Y_OVERFLOW) != 0 {
        return  // Ignore overflow
    }
    
    // Update position
    mouse_x += int(x)
    mouse_y -= int(y)  // Invert Y for screen coordinates
    
    // Clamp to screen bounds (if handler provides bounds)
    // Done in event handler
    
    // Call event handler
    if event_handler != nil {
        event_handler(mouse_x, mouse_y, mouse_z, mouse_buttons)
    }
}


// Set Event Handler
set_event_handler :: proc(handler: Mouse_Event_Handler) {
    event_handler = handler
}


// Get Mouse Position
get_position :: proc() -> (x: int, y: int) {
    return mouse_x, mouse_y
}


// Set Mouse Position
set_position :: proc(x: int, y: int) {
    mouse_x = x
    mouse_y = y
}


// Get Button State
get_buttons :: proc() -> u8 {
    return mouse_buttons
}


// Is Button Pressed
is_button_pressed :: proc(button: u8) -> bool {
    return (mouse_buttons & button) != 0
}


// Get Wheel Position
get_wheel :: proc() -> int {
    return mouse_z
}


// Reset Position
reset_position :: proc() {
    mouse_x = 0
    mouse_y = 0
    mouse_z = 0
}


// Is Initialized
is_initialized :: proc() -> bool {
    return mouse_initialized
}


// Is Present
is_present :: proc() -> bool {
    return mouse_present
}
