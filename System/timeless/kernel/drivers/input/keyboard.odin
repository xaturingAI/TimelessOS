// PS/2 Keyboard Driver
// Handles keyboard input via PS/2 controller

package drivers.input.keyboard

import (
    "core:log"
    "core:ring_buffer"
    "arch:x86_64/io"
    "interrupts:pic"
)

// PS/2 Controller Ports
PS2_DATA ::   0x60
PS2_STATUS :: 0x64
PS2_COMMAND :: 0x64

// PS/2 Commands
PS2_CMD_READ_CONFIG ::      0x20
PS2_CMD_WRITE_CONFIG ::     0x60
PS2_CMD_DISABLE_PORT ::     0xAD
PS2_CMD_ENABLE_PORT ::      0xAE
PS2_CMD_TEST_PORT ::        0xAC
PS2_CMD_SEND_TO_DEVICE ::   0xD4
PS2_CMD_REBOOT ::           0xFE

// PS/2 Device Commands
PS2_DEV_SET_DEFAULTS ::     0xF6
PS2_DEV_ENABLE ::           0xF4
PS2_DEV_DISABLE ::          0xF5
PS2_DEV_RESET ::            0xFF
PS2_DEV_SET_SCANCODE ::     0xF0
PS2_DEV_GET_ID ::           0xF2

// PS/2 Status Register Bits
PS2_STATUS_OUTPUT_FULL ::   (1 << 0)
PS2_STATUS_INPUT_FULL ::    (1 << 1)
PS2_STATUS_SYSTEM_FLAG ::   (1 << 2)
PS2_STATUS_COMMAND_DATA ::  (1 << 3)
PS2_STATUS_TIMEOUT_ERROR :: (1 << 6)
PS2_STATUS_PARITY_ERROR ::  (1 << 7)

// PS/2 Configuration Bits
PS2_CONFIG_FIRST_PORT ::    (1 << 0)
PS2_CONFIG_SECOND_PORT ::   (1 << 1)
PS2_CONFIG_SYSTEM_FLAG ::   (1 << 2)
PS2_CONFIG_FIRST_INT ::     (1 << 4)
PS2_CONFIG_SECOND_INT ::    (1 << 5)
PS2_CONFIG_TRANSLATE ::     (1 << 6)

// Keyboard Response Codes
PS2_ACK :: 0xFA
PS2_RESEND :: 0xFE
PS2_ERROR :: 0xFC

// Scancode Set 1 Make Codes
SCAN_ESCAPE :: 0x01
SCAN_1 :: 0x02
SCAN_2 :: 0x03
SCAN_3 :: 0x04
SCAN_4 :: 0x05
SCAN_5 :: 0x06
SCAN_6 :: 0x07
SCAN_7 :: 0x08
SCAN_8 :: 0x09
SCAN_9 :: 0x0A
SCAN_0 :: 0x0B
SCAN_MINUS :: 0x0C
SCAN_EQUALS :: 0x0D
SCAN_BACKSPACE :: 0x0E
SCAN_TAB :: 0x0F
SCAN_Q :: 0x10
SCAN_W :: 0x11
SCAN_E :: 0x12
SCAN_R :: 0x13
SCAN_T :: 0x14
SCAN_Y :: 0x15
SCAN_U :: 0x16
SCAN_I :: 0x17
SCAN_O :: 0x18
SCAN_P :: 0x19
SCAN_LBRACKET :: 0x1A
SCAN_RBRACKET :: 0x1B
SCAN_ENTER :: 0x1C
SCAN_LCTRL :: 0x1D
SCAN_A :: 0x1E
SCAN_S :: 0x1F
SCAN_D :: 0x20
SCAN_F :: 0x21
SCAN_G :: 0x22
SCAN_H :: 0x23
SCAN_J :: 0x24
SCAN_K :: 0x25
SCAN_L :: 0x26
SCAN_SEMICOLON :: 0x27
SCAN_QUOTE :: 0x28
SCAN_GRAVE :: 0x29
SCAN_LSHIFT :: 0x2A
SCAN_BACKSLASH :: 0x2B
SCAN_Z :: 0x2C
SCAN_X :: 0x2D
SCAN_C :: 0x2E
SCAN_V :: 0x2F
SCAN_B :: 0x30
SCAN_N :: 0x31
SCAN_M :: 0x32
SCAN_COMMA :: 0x33
SCAN_PERIOD :: 0x34
SCAN_SLASH :: 0x35
SCAN_RSHIFT :: 0x36
SCAN_KPASTERISK :: 0x37
SCAN_LALT :: 0x38
SCAN_SPACE :: 0x39
SCAN_CAPSLOCK :: 0x3A
SCAN_F1 :: 0x3B
SCAN_F2 :: 0x3C
SCAN_F3 :: 0x3D
SCAN_F4 :: 0x3E
SCAN_F5 :: 0x3F
SCAN_F6 :: 0x40
SCAN_F7 :: 0x41
SCAN_F8 :: 0x42
SCAN_F9 :: 0x43
SCAN_F10 :: 0x44
SCAN_NUMLOCK :: 0x45
SCAN_SCROLLLOCK :: 0x46
SCAN_KP7 :: 0x47
SCAN_KP8 :: 0x48
SCAN_KP9 :: 0x49
SCAN_KPMINUS :: 0x4A
SCAN_KP4 :: 0x4B
SCAN_KP5 :: 0x4C
SCAN_KP6 :: 0x4D
SCAN_KPPLUS :: 0x4E
SCAN_KP1 :: 0x4F
SCAN_KP2 :: 0x50
SCAN_KP3 :: 0x51
SCAN_KP0 :: 0x52
SCAN_KPPERIOD :: 0x53
SCAN_F11 :: 0x57
SCAN_F12 :: 0x58

// Extended key prefix
SCAN_EXTENDED :: 0xE0

// Key State
modifier_state: u8 = 0
MOD_LSHIFT :: (1 << 0)
MOD_RSHIFT :: (1 << 1)
MOD_LCTRL ::  (1 << 2)
MOD_RCTRL ::  (1 << 3)
MOD_LALT ::   (1 << 4)
MOD_RALT ::   (1 << 5)
MOD_CAPS ::   (1 << 6)
MOD_NUMLOCK :: (1 << 7)

// Input Buffer
INPUT_BUFFER_SIZE :: 256
input_buffer: ring_buffer.Buffer(input_buffer_size=INPUT_BUFFER_SIZE)

// Driver State
keyboard_initialized: bool = false
keyboard_present: bool = false
scan_code_set: int = 2  // Default to set 2


// Initialize Keyboard
init :: proc() {
    log.info("Keyboard: Initializing PS/2 keyboard...")
    
    // Wait for controller to be ready
    wait_ready()
    
    // Disable keyboard
    write_command(PS2_CMD_DISABLE_PORT)
    
    // Flush output buffer
    flush_buffer()
    
    // Enable keyboard
    write_command(PS2_CMD_ENABLE_PORT)
    
    // Set scan code set to 2 (default for most keyboards)
    set_scan_code_set(2)
    
    // Enable keyboard device
    send_to_keyboard(PS2_DEV_ENABLE)
    
    // Register IRQ handler (IRQ1 -> vector 33)
    // Done in IDT setup
    
    keyboard_initialized = true
    keyboard_present = true
    
    log.info("Keyboard: PS/2 keyboard initialized")
}


// Wait for Controller Ready
wait_ready :: proc() {
    timeout := 100000
    for timeout > 0 {
        status := io.inb(PS2_STATUS)
        if (status & PS2_STATUS_INPUT_FULL) == 0 {
            return
        }
        timeout--
    }
    log.warn("Keyboard: Controller timeout")
}


// Wait for Output Data
wait_output :: proc() -> u8 {
    timeout := 100000
    while timeout > 0 {
        status := io.inb(PS2_STATUS)
        if (status & PS2_STATUS_OUTPUT_FULL) != 0 {
            return io.inb(PS2_DATA)
        }
        timeout--
    }
    return 0
}


// Write to Controller
write_command :: proc(cmd: u8) {
    wait_ready()
    io.outb(PS2_COMMAND, cmd)
}


// Write Data to Controller
write_data :: proc(data: u8) {
    wait_ready()
    io.outb(PS2_DATA, data)
}


// Send Command to Keyboard
send_to_keyboard :: proc(data: u8) -> bool {
    write_command(PS2_CMD_SEND_TO_DEVICE)
    wait_ready()
    io.outb(PS2_DATA, data)
    
    // Wait for ACK
    response := wait_output()
    if response == PS2_ACK {
        return true
    } else if response == PS2_RESEND {
        // Retry once
        send_to_keyboard(data)
    }
    return false
}


// Flush Output Buffer
flush_buffer :: proc() {
    timeout := 100
    for timeout > 0 {
        status := io.inb(PS2_STATUS)
        if (status & PS2_STATUS_OUTPUT_FULL) != 0 {
            _ = io.inb(PS2_DATA)
        } else {
            break
        }
        timeout--
    }
}


// Set Scan Code Set
set_scan_code_set :: proc(set: int) -> bool {
    send_to_keyboard(PS2_DEV_SET_SCANCODE)
    send_to_keyboard(u8(set))
    scan_code_set = set
    return true
}


// Handle Keyboard IRQ (called from IDT)
handle_irq :: proc() {
    if !keyboard_initialized {
        return
    }
    
    // Read scancode
    scancode := io.inb(PS2_DATA)
    
    // Process scancode
    process_scancode(scancode)
}


// Process Scancode
process_scancode :: proc(scancode: u8) {
    static extended := false
    static release := false
    
    // Check for extended prefix
    if scancode == SCAN_EXTENDED {
        extended = true
        return
    }
    
    // Check for release (bit 7 set in set 1, or 0xF0 in set 2)
    if scan_code_set == 1 {
        release = (scancode & 0x80) != 0
        if release {
            scancode &= 0x7F
        }
    } else if scan_code_set == 2 {
        if scancode == 0xF0 {
            release = true
            return
        }
    }
    
    // Handle extended keys
    if extended {
        handle_extended_key(scancode, release)
        extended = false
        release = false
        return
    }
    
    // Handle regular keys
    handle_key(scancode, release)
    release = false
}


// Handle Regular Key
handle_key :: proc(scancode: u8, release: bool) {
    key_code := scancode_to_keycode(scancode)
    
    if key_code == 0 {
        return
    }
    
    if release {
        // Key released - update modifiers
        update_modifier(key_code, false)
    } else {
        // Key pressed - update modifiers and add to buffer
        update_modifier(key_code, true)
        
        if is_modifier(key_code) {
            return
        }
        
        // Convert to ASCII with modifiers
        c := keycode_to_ascii(key_code)
        if c != 0 {
            input_buffer.push(c)
        }
    }
}


// Handle Extended Key
handle_extended_key :: proc(scancode: u8, release: bool) {
    // Extended keys: arrow keys, right ctrl/alt, etc.
    switch scancode {
    case 0x1C:  // Right Enter
        // Handle
    case 0x1D:  // Right Ctrl
        if !release {
            modifier_state |= MOD_RCTRL
        } else {
            modifier_state &= ~MOD_RCTRL
        }
    case 0x35:  // KP Slash
        // Handle
    case 0x38:  // Right Alt
        if !release {
            modifier_state |= MOD_RALT
        } else {
            modifier_state &= ~MOD_RALT
        }
    case 0x47:  // Home (arrow)
        if !release {
            input_buffer.push(1)  // SOH
        }
    case 0x48:  // Up
        if !release {
            input_buffer.push(16)  // DLE
        }
    case 0x49:  // Page Up
        if !release {
            input_buffer.push(17)  // DC1
        }
    case 0x4B:  // Left
        if !release {
            input_buffer.push(18)  // DC2
        }
    case 0x4D:  // Right
        if !release {
            input_buffer.push(19)  // DC3
        }
    case 0x4F:  // End
        if !release {
            input_buffer.push(5)  // ENQ
        }
    case 0x50:  // Down
        if !release {
            input_buffer.push(14)  // SO
        }
    case 0x51:  // Page Down
        if !release {
            input_buffer.push(6)  // ACK
        }
    case 0x52:  // Insert
        if !release {
            input_buffer.push(21)  // NAK
        }
    case 0x53:  // Delete
        if !release {
            input_buffer.push(127)  // DEL
        }
    }
}


// Update Modifier State
update_modifier :: proc(key_code: u8, pressed: bool) {
    switch key_code {
    case 1:  // LSHIFT
        if pressed { modifier_state |= MOD_LSHIFT } else { modifier_state &= ~MOD_LSHIFT }
    case 2:  // RSHIFT
        if pressed { modifier_state |= MOD_RSHIFT } else { modifier_state &= ~MOD_RSHIFT }
    case 3:  // LCTRL
        if pressed { modifier_state |= MOD_LCTRL } else { modifier_state &= ~MOD_LCTRL }
    case 4:  // RCTRL
        if pressed { modifier_state |= MOD_RCTRL } else { modifier_state &= ~MOD_RCTRL }
    case 5:  // LALT
        if pressed { modifier_state |= MOD_LALT } else { modifier_state &= ~MOD_LALT }
    case 6:  // RALT
        if pressed { modifier_state |= MOD_RALT } else { modifier_state &= ~MOD_RALT }
    case 7:  // CAPSLOCK
        if pressed { modifier_state ^= MOD_CAPS }
    case 8:  // NUMLOCK
        if pressed { modifier_state ^= MOD_NUMLOCK }
    }
}


// Check if Key is Modifier
is_modifier :: proc(key_code: u8) -> bool {
    return key_code <= 8
}


// Scancode to Keycode Mapping
scancode_to_keycode :: proc(scancode: u8) -> u8 {
    switch scancode {
    case SCAN_LSHIFT: return 1
    case SCAN_RSHIFT: return 2
    case SCAN_LCTRL: return 3
    case 0x1D: return 4  // Right Ctrl (extended)
    case SCAN_LALT: return 5
    case 0x38: return 6  // Right Alt (extended)
    case SCAN_CAPSLOCK: return 7
    case SCAN_NUMLOCK: return 8
    }
    return scancode  // Regular keys return scancode as keycode
}


// Keycode to ASCII
keycode_to_ascii :: proc(key_code: u8) -> u8 {
    // Shift state
    shifted := (modifier_state & (MOD_LSHIFT | MOD_RSHIFT)) != 0
    caps := (modifier_state & MOD_CAPS) != 0
    
    // For letters
    if key_code >= SCAN_A && key_code <= SCAN_Z {
        letter := key_code - SCAN_A
        if (caps && !shifted) || (!caps && shifted) {
            return u8('A' + letter)
        } else {
            return u8('a' + letter)
        }
    }
    
    // Numbers and symbols
    switch key_code {
    case SCAN_0: return if shifted then ')' else '0'
    case SCAN_1: return if shifted then '!' else '1'
    case SCAN_2: return if shifted then '@' else '2'
    case SCAN_3: return if shifted then '#' else '3'
    case SCAN_4: return if shifted then '$' else '4'
    case SCAN_5: return if shifted then '%' else '5'
    case SCAN_6: return if shifted then '^' else '6'
    case SCAN_7: return if shifted then '&' else '7'
    case SCAN_8: return if shifted then '*' else '8'
    case SCAN_9: return if shifted then '(' else '9'
    case SCAN_MINUS: return if shifted then '_' else '-'
    case SCAN_EQUALS: return if shifted then '+' else '='
    case SCAN_SPACE: return ' '
    case SCAN_TAB: return '\t'
    case SCAN_ENTER: return '\n'
    case SCAN_BACKSPACE: return '\b'
    case SCAN_ESCAPE: return 27  // ESC
    case SCAN_LBRACKET: return if shifted then '{' else '['
    case SCAN_RBRACKET: return if shifted then '}' else ']'
    case SCAN_SEMICOLON: return if shifted then ':' else ';'
    case SCAN_QUOTE: return if shifted then '"' else '\''
    case SCAN_GRAVE: return if shifted then '~' else '`'
    case SCAN_BACKSLASH: return if shifted then '|' else '\\'
    case SCAN_COMMA: return if shifted then '<' else ','
    case SCAN_PERIOD: return if shifted then '>' else '.'
    case SCAN_SLASH: return if shifted then '?' else '/'
    }
    
    return 0
}


// Read Character (blocking)
read_char :: proc() -> u8 {
    for {
        if c, ok := input_buffer.pop() {
            return c
        }
        asm { hlt }  // Wait for interrupt
    }
}


// Read Character (non-blocking)
try_read_char :: proc() -> (u8, bool) {
    return input_buffer.pop()
}


// Read Line
read_line :: proc(buffer: []u8, max_len: int) -> int {
    count := 0
    for count < max_len - 1 {
        c := read_char()
        
        if c == '\n' || c == '\r' {
            if count > 0 {
                break
            }
            continue
        }
        
        if c == '\b' {
            if count > 0 {
                count--
            }
            continue
        }
        
        if c >= 32 {
            buffer[count] = c
            count++
        }
    }
    
    buffer[count] = 0
    return count
}


// Check if Data Available
data_available :: proc() -> bool {
    return !input_buffer.is_empty()
}


// Get Modifier State
get_modifiers :: proc() -> u8 {
    return modifier_state
}


// Is Initialized
is_initialized :: proc() -> bool {
    return keyboard_initialized
}
