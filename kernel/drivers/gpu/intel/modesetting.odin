// Intel Integrated Graphics Driver - Modesetting
// Display Mode Setting, PLL Configuration, and Panel Management

package drivers.gpu.intel

import (
    "core:log"
    "core:math"
)

// Display Connector Types
CONNECTOR_TYPE :: enum {
    Unknown,
    VGA,
    DVI_D,
    DVI_I,
    HDMI,
    DisplayPort,
    eDP,
    LVDS,
    DSI,
}

// Display Pipe Configuration
DISPLAY_PIPE :: enum {
    Pipe_A,
    Pipe_B,
    Pipe_C,
    Pipe_D,
}

// PLL (Phase Locked Loop) Types
PLL_TYPE :: enum {
    PLL_NONE,
    PLL_LEGACY,
    PLL_DDI,
    PLL_DPLL4,
}

// Display Mode Timing
Mode_Timing :: struct {
    clock:      u32,  // Pixel clock in kHz
    hdisplay:   u32,  // Active horizontal pixels
    hsync_start: u32, // Horizontal sync start
    hsync_end:   u32, // Horizontal sync end
    htotal:      u32, // Total horizontal pixels
    vdisplay:   u32,  // Active vertical lines
    vsync_start: u32, // Vertical sync start
    vsync_end:   u32, // Vertical sync end
    vtotal:      u32, // Total vertical lines
    flags:       u32, // Mode flags (hsync/vsync polarity)
}

// Common Display Modes
MODE_1920x1080_60 :: Mode_Timing {
    clock: 148500,
    hdisplay: 1920, hsync_start: 2008, hsync_end: 2052, htotal: 2200,
    vdisplay: 1080, vsync_start: 1084, vsync_end: 1089, vtotal: 1125,
    flags: 0,
}

MODE_1280x720_60 :: Mode_Timing {
    clock: 74250,
    hdisplay: 1280, hsync_start: 1390, hsync_end: 1430, htotal: 1650,
    vdisplay: 720, vsync_start: 725, vsync_end: 730, vtotal: 750,
    flags: 0,
}

MODE_1024x768_60 :: Mode_Timing {
    clock: 65000,
    hdisplay: 1024, hsync_start: 1048, hsync_end: 1184, htotal: 1344,
    vdisplay: 768, vsync_start: 771, vsync_end: 777, vtotal: 806,
    flags: 0,
}

MODE_800x600_60 :: Mode_Timing {
    clock: 40000,
    hdisplay: 800, hsync_start: 840, hsync_end: 968, htotal: 1056,
    vdisplay: 600, vsync_start: 601, vsync_end: 605, vtotal: 628,
    flags: 0,
}

// Connector State
Connector_State :: struct {
    type: CONNECTOR_TYPE,
    connected: bool,
    edid_valid: bool,
    edid_data: [128]u8,
    preferred_mode: Mode_Timing,
    pipe: DISPLAY_PIPE,
    encoder_id: u32,
}

// Encoder State
Encoder_State :: struct {
    type: CONNECTOR_TYPE,
    active: bool,
    pipe: DISPLAY_PIPE,
    pll: PLL_TYPE,
    pll_id: u32,
}

// Display Pipe State
Pipe_State :: struct {
    active: bool,
    mode: Mode_Timing,
    bpp: u32,
    format: Pixel_Format,
    enabled: bool,
}

// DDI (Digital Display Interface) Buffer Translation
DDI_BUFFER_TRANSLATION :: struct {
    translatioN: [5]u8,  // 5 voltage swing levels
    n_entries: u32,
}

// Global Display State
connectors: [4]Connector_State
encoders: [4]Encoder_State
pipes: [4]Pipe_State
active_pipe_count: u32 = 0
ddi_buffer_trans: DDI_BUFFER_TRANSLATION


// Initialize Display Controller
init_display_controller :: proc() -> bool {
    log.info("Intel GPU: Initializing display controller...")
    
    // Reset display engine
    reset_display_engine()
    
    // Initialize DDI buffers
    init_ddi_buffers()
    
    // Detect and initialize connectors
    detect_connectors()
    
    // Initialize PLLs
    if !init_plls() {
        return false
    }
    
    return true
}


// Reset Display Engine
reset_display_engine :: proc() {
    DISPLAY_CTRL_RESET :: 0x64800
    
    // Assert reset
    mmio_write(DISPLAY_CTRL_RESET, 1)
    
    // Wait for reset to complete
    for _ in 0..<100 {
        if (mmio_read(DISPLAY_CTRL_RESET) & 1) == 0 {
            break
        }
    }
    
    // Deassert reset
    mmio_write(DISPLAY_CTRL_RESET, 0)
}


// Initialize DDI Buffers
init_ddi_buffers :: proc() {
    // DDI buffer translations for different link rates
    // These values are platform-specific
    
    DDI_BUF_TRANS_A :: 0x64800
    DDI_BUF_TRANS_B :: 0x64804
    DDI_BUF_TRANS_C :: 0x64808
    DDI_BUF_TRANS_D :: 0x6480C
    DDI_BUF_TRANS_E :: 0x64810
    
    // Default translations for HSW/BDW
    ddi_buffer_trans = DDI_BUFFER_TRANSLATION{
        translation = [5]u8{0x0A, 0x55, 0x52, 0x00, 0x0A},
        n_entries = 5,
    }
    
    // Program DDI buffer translations
    for i in 0..<ddi_buffer_trans.n_entries {
        value := u32(ddi_buffer_trans.translation[i])
        mmio_write(DDI_BUF_TRANS_A + (i * 4), value)
    }
    
    log.info("Intel GPU: DDI buffers initialized")
}


// Detect Connected Displays
detect_connectors :: proc() {
    log.info("Intel GPU: Detecting display connectors...")
    
    // Check each DDI port (A through E)
    for port in 0..<5 {
        connector_idx := port
        
        // Read DDI status register
        DDI_STATUS :: 0x64800 + (port * 0x100)
        status := mmio_read(DDI_STATUS)
        
        // Check if port is connected (bit 0)
        connected := (status & 1) != 0
        
        connectors[connector_idx] = Connector_State{
            type = detect_connector_type(port),
            connected = connected,
            edid_valid = false,
        }
        
        if connected {
            log.info("Intel GPU: Port %c connected", 'A' + port)
            // Read EDID
            read_edid(port, &connectors[connector_idx])
        }
    }
}


// Detect Connector Type
detect_connector_type :: proc(port: u32) -> CONNECTOR_TYPE {
    // Check VBT (Video BIOS Table) or platform data
    // For now, assume DDI-A is eDP (laptop), others are HDMI/DP
    
    switch port {
    case 0: return .eDP  // DDI-A - internal panel
    case 1: return .HDMI // DDI-B - external
    case 2: return .DisplayPort  // DDI-C
    case 3: return .HDMI // DDI-D
    case 4: return .DisplayPort  // DDI-E
    case: return .Unknown
    }
}


// Read EDID from Display
read_edid :: proc(port: u32, connector: *Connector_State) {
    // Access DDC (Display Data Channel) to read EDID
    // This uses I2C-over-AUX for DisplayPort or DDC for HDMI
    
    GMBUS_CTRL :: 0x5100
    GMBUS_DATA :: 0x5104
    GMBUS_STATUS :: 0x5108
    
    // Select DDC bus based on port
    ddc_bus := port + 1  // GMBUS port mapping
    
    // Set DDC clock and enable
    mmio_write(GMBUS_CTRL, (ddc_bus << 8) | 0x01)
    
    // Read EDID (128 bytes in 16-byte chunks)
    offset := 0
    for offset < 128 {
        // Write EDID offset
        mmio_write(GMBUS_DATA, u32(offset))
        
        // Read 16 bytes
        for i in 0..<16 {
            connector.edid_data[offset + i] = cast(u8)(mmio_read(GMBUS_DATA))
            offset++
        }
    }
    
    // Validate EDID checksum
    checksum := u8(0)
    for i in 0..<128 {
        checksum += connector.edid_data[i]
    }
    
    if checksum == 0 {
        connector.edid_valid = true
        log.info("Intel GPU: EDID valid for port %c", 'A' + port)
        
        // Parse preferred mode from EDID
        parse_edid_mode(connector)
    } else {
        log.warn("Intel GPU: EDID checksum invalid")
        // Use default mode
        connector.preferred_mode = MODE_1920x1080_60
    }
}


// Parse EDID for Preferred Mode
parse_edid_mode :: proc(connector: *Connector_State) {
    // Parse detailed timing descriptor at offset 0x36
    edid := &connector.edid_data[0]
    
    if edid[0x36] == 0 && edid[0x37] == 0 {
        // Found detailed timing descriptor
        hactive := u32(edid[0x38]) | (u32(edid[0x3A] & 0xF0) << 4)
        vactive := u32(edid[0x3B]) | (u32(edid[0x3D] & 0xF0) << 4)
        
        hblank := u32(edid[0x39]) | (u32(edid[0x3A] & 0x0F) << 8)
        vblank := u32(edid[0x3C]) | (u32(edid[0x3D] & 0x0F) << 8)
        
        clock := u32(edid[0x36 + 0x02]) | (u32(edid[0x36 + 0x03]) << 8)
        clock *= 10  // Convert to kHz
        
        connector.preferred_mode = Mode_Timing{
            clock = clock,
            hdisplay = hactive,
            htotal = hactive + hblank,
            vdisplay = vactive,
            vtotal = vactive + vblank,
            // Simplified - would need full parsing
            hsync_start = hactive + 48,
            hsync_end = hactive + 88,
            vsync_start = vactive + 3,
            vsync_end = vactive + 6,
        }
        
        log.info("Intel GPU: Preferred mode %dx%d @ %d kHz", 
                 hactive, vactive, clock)
    }
}


// Initialize PLLs
init_plls :: proc() -> bool {
    log.info("Intel GPU: Initializing PLLs...")
    
    // Enable DPLL4 (Gen9+)
    DPLL_CTRL1 :: 0x46010
    DPLL_ENABLE :: (1 << 31)
    
    // Enable DPLL
    mmio_write(DPLL_CTRL1, DPLL_ENABLE)
    
    // Wait for PLL to lock
    timeout := 1000
    for timeout > 0 {
        status := mmio_read(DPLL_CTRL1)
        if (status & (1 << 30)) != 0 {  // PLL locked
            break
        }
        timeout--
    }
    
    if timeout == 0 {
        log.error("Intel GPU: PLL failed to lock")
        return false
    }
    
    log.info("Intel GPU: PLL initialized and locked")
    return true
}


// Calculate PLL Dividers for Mode
calculate_pll_dividers :: proc(mode: *Mode_Timing, out_dividers: *u32) {
    // Reference clock is typically 24 MHz or 19.2 MHz
    REF_CLOCK :: 24000  // 24 MHz in kHz
    
    // Target PLL frequency (depends on platform)
    // For Gen9+: 24 MHz * (fb_div + frac/5) / div1 / div2
    
    pixel_clock := mode.clock
    
    // Find best dividers
    // Simplified calculation - real implementation needs full search
    
    best_dividers := u32(0)
    best_error := u64(math.MAX_U64)
    
    for div2 in 1..<8 {
        for div1 in 1..<8 {
            for fb in 20..<200 {
                calculated := (REF_CLOCK * fb) / (div1 * div2)
                
                error := calculated - pixel_clock
                if error < 0 { error = -error }
                
                if error < best_error {
                    best_error = error
                    best_dividers = (fb << 16) | (div1 << 8) | div2
                }
            }
        }
    }
    
    out_dividers[] = best_dividers
}


// Program PLL for Mode
program_pll :: proc(pipe: DISPLAY_PIPE, mode: *Mode_Timing) -> bool {
    var dividers: u32
    
    calculate_pll_dividers(mode, &dividers)
    
    // DDI PLL registers (Gen9+)
    DPLL_CFGCR1 :: 0x46014
    DPLL_CFGCR2 :: 0x46018
    DPLL_ENABLE :: 0x46010
    
    // Enable PLL for this pipe
    pll_enable := DPLL_ENABLE | (cast(u32)(pipe) << 24)
    mmio_write(DPLL_ENABLE, pll_enable)
    
    // Program dividers
    mmio_write(DPLL_CFGCR1, dividers)
    mmio_write(DPLL_CFGCR2, 0)  // Fractional part
    
    // Wait for PLL lock
    timeout := 1000
    for timeout > 0 {
        status := mmio_read(DPLL_CFGCR1)
        if (status & (1 << 30)) != 0 {
            return true
        }
        timeout--
    }
    
    return false
}


// Enable Display Pipe
enable_pipe :: proc(pipe: DISPLAY_PIPE, mode: *Mode_Timing) -> bool {
    log.info("Intel GPU: Enabling pipe %d with mode %dx%d", 
             pipe, mode.hdisplay, mode.vdisplay)
    
    // Pipe configuration registers
    PIPE_CONF :: 0x70008 + (pipe * 0x1000)
    PIPE_DATA_M1 :: 0x70010 + (pipe * 0x1000)
    PIPE_DATA_N1 :: 0x70014 + (pipe * 0x1000)
    
    // Configure pipe
    pipe_conf := (3 << 30)  // 8bpc
    pipe_conf |= (1 << 21)  // VSYNC enable
    pipe_conf |= (1 << 31)  // Pipe enable
    
    mmio_write(PIPE_CONF, pipe_conf)
    
    // Program data M/N for link training (DP)
    mmio_write(PIPE_DATA_M1, mode.clock)
    mmio_write(PIPE_DATA_N1, mode.clock)
    
    pipes[pipe].active = true
    pipes[pipe].mode = mode[]
    pipes[pipe].enabled = true
    
    return true
}


// Enable Display Plane
enable_plane :: proc(pipe: DISPLAY_PIPE, fb_phys: u32, stride: u32) {
    // Plane control registers
    PLANE_CTRL :: 0x70180 + (pipe * 0x1000)
    PLANE_SURF :: 0x7019C + (pipe * 0x1000)
    PLANE_STRIDE :: 0x70104 + (pipe * 0x1000)
    
    // Enable plane
    plane_ctrl := (1 << 31)  // Plane enable
    plane_ctrl |= (1 << 9)   // Async mode
    
    mmio_write(PLANE_CTRL, plane_ctrl)
    mmio_write(PLANE_SURF, fb_phys)
    mmio_write(PLANE_STRIDE, stride)
}


// Set Display Mode (Main Entry Point)
set_display_mode :: proc(width: u32, height: u32, bpp: u32) -> bool {
    log.info("Intel GPU: Setting display mode %dx%d@%d", width, height, bpp)
    
    // Find matching mode
    var mode: Mode_Timing
    
    if width == 1920 && height == 1080 {
        mode = MODE_1920x1080_60
    } else if width == 1280 && height == 720 {
        mode = MODE_1280x720_60
    } else if width == 1024 && height == 768 {
        mode = MODE_1024x768_60
    } else if width == 800 && height == 600 {
        mode = MODE_800x600_60
    } else {
        log.error("Intel GPU: Unsupported mode %dx%d", width, height)
        return false
    }
    
    // Use Pipe A for primary display
    pipe := DISPLAY_PIPE.Pipe_A
    
    // Program PLL
    if !program_pll(pipe, &mode) {
        log.error("Intel GPU: Failed to program PLL")
        return false
    }
    
    // Enable pipe
    if !enable_pipe(pipe, &mode) {
        log.error("Intel GPU: Failed to enable pipe")
        return false
    }
    
    // Enable plane with framebuffer
    stride := width * (bpp / 8)
    fb_phys := u32(intel_device.bar1)
    enable_plane(pipe, fb_phys, stride)
    
    // Update current mode
    intel_current_mode = Graphics_Mode{
        width = width,
        height = height,
        bpp = bpp,
        pitch = stride,
        format = .ARGB8888,
        framebuffer = intel_fb_base,
        size = intel_fb_size,
    }
    
    log.info("Intel GPU: Mode set successfully")
    return true
}
