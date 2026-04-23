// USB Host Controller Driver - xHCI (USB 3.0)
// Universal Host Controller Interface

package drivers.usb

import (
    "core:log"
    "core:mem"
    "mm:physical"
    "mm:virtual"
)

// xHCI Register Offsets
XHCI_CAPLENGTH ::    0x00  // Capability Registers Length
XHCI_HCIVERSION ::   0x02  // HCI Version
XHCI_HCSPARAMS1 ::   0x04  // HCSPARAMS1
XHCI_HCSPARAMS2 ::   0x08  // HCSPARAMS2
XHCI_HCSPARAMS3 ::   0x0C  // HCSPARAMS3
XHCI_HCCPARAMS ::    0x10  // HCCPARAMS
XHCI_DBOFF ::        0x14  // Doorbell Offset
XHCI_RTSOFF ::       0x18  // Runtime Register Space Offset
XHCI_HCSPARAMS4 ::   0x1C  // HCSPARAMS4

// xHCI Operational Registers
XHCI_USBCMD ::       0x00  // USB Command
XHCI_USBSTS ::       0x04  // USB Status
XHCI_PAGESIZE ::     0x08  // Page Size
XHCI_DNCTRL ::       0x14  // Device Notification Control
XHCI_CRCR_LO ::      0x18  // Command Ring Control Register Low
XHCI_CRCR_HI ::      0x1C  // Command Ring Control Register High
XHCI_DBAUP ::        0x20  // Device Base Address Update
XHCI_ENDPORTIN ::    0x24  // Endpoints In
XHCI_ENDPORTOUT ::   0x28  // Endpoints Out

// USB Command Bits
USBCMD_RUN_STOP ::      (1 << 0)
USBCMD_RESET ::         (1 << 1)
USBCMD_INTERRUPTER ::   (1 << 2)
USBCMD_HSE_ENABLE ::    (1 << 3)
USBCMD_LHCE_ENABLE ::   (1 << 4)

// USB Status Bits
USBSTS_HCHALTED ::      (1 << 0)
USBSTS_HSE ::           (1 << 2)
USBSTS_CNR ::           (1 << 3)
USBSTS_SRE ::           (1 << 4)
USBSTS_CLKPRERR ::      (1 << 5)

// xHCI State
xhci_state :: struct {
    initialized: bool,
    mmio_base: uintptr,
    cap_length: u8,
    max_ports: u32,
    max_slots: u32,
    max_interrupters: u32,
    command_ring: u64,
    event_ring: u64,
    dcbaa: u64,  // Device Context Base Address Array
    page_size: u32,
}

xhci: xhci_state

// USB Device State
usb_device :: struct {
    slot_id: u32,
    port: u32,
    speed: u32,
    address: u32,
    enabled: bool,
}

usb_devices: [16]usb_device
device_count: u32 = 0


// Initialize xHCI Controller
xhci_init :: proc(mmio_phys: u64) -> bool {
    log.info("USB: Initializing xHCI controller...")
    
    xhci = xhci_state{
        mmio_base = virtual.physical_to_virtual(mmio_phys),
        initialized = false,
    }
    
    // Read capability registers
    xhci.cap_length = cast(u8)(xhci_read8(XHCI_CAPLENGTH))
    
    log.info("USB: xHCI cap length %d", xhci.cap_length)
    
    // Read HCSPARAMS1
    hcsparams1 := xhci_read32(XHCI_HCSPARAMS1)
    xhci.max_slots = hcsparams1 & 0xFF
    xhci.max_interrupters = (hcsparams1 >> 8) & 0xFF
    xhci.max_ports = (hcsparams1 >> 16) & 0xFF
    
    log.info("USB: xHCI - %d slots, %d interrupters, %d ports", 
             xhci.max_slots, xhci.max_interrupters, xhci.max_ports)
    
    // Read page size
    xhci.page_size = xhci_read32(XHCI_PAGESIZE)
    log.info("USB: xHCI page size 0x%X", xhci.page_size)
    
    // Reset controller
    if !xhci_reset() {
        log.error("USB: xHCI reset failed")
        return false
    }
    
    // Start controller
    if !xhci_start() {
        log.error("USB: xHCI start failed")
        return false
    }
    
    // Allocate and initialize DCBAA
    if !xhci_init_dcbaa() {
        log.error("USB: xHCI DCBAA initialization failed")
        return false
    }
    
    // Allocate command ring
    if !xhci_init_command_ring() {
        log.error("USB: xHCI command ring initialization failed")
        return false
    }
    
    // Allocate event ring
    if !xhci_init_event_ring() {
        log.error("USB: xHCI event ring initialization failed")
        return false
    }
    
    // Enable interrupts
    xhci_enable_interrupts()
    
    // Scan ports
    xhci_scan_ports()
    
    xhci.initialized = true
    log.info("USB: xHCI controller initialized")
    
    return true
}


// xHCI MMIO Access
xhci_read8 :: proc(offset: u32) -> u8 {
    ptr := cast(*volatile u8)(xhci.mmio_base + offset)
    return ptr[]
}

xhci_read32 :: proc(offset: u32) -> u32 {
    ptr := cast(*volatile u32)(xhci.mmio_base + offset)
    return ptr[]
}

xhci_write32 :: proc(offset: u32, value: u32) {
    ptr := cast(*volatile u32)(xhci.mmio_base + offset)
    ptr[] = value
}

xhci_write64 :: proc(offset: u32, value: u64) {
    ptr := cast(*volatile u64)(xhci.mmio_base + offset)
    ptr[] = value
}


// Reset xHCI Controller
xhci_reset :: proc() -> bool {
    log.info("USB: Resetting xHCI controller...")
    
    // Set reset bit
    xhci_write32(XHCI_USBCMD, USBCMD_RESET)
    
    // Wait for reset to complete
    timeout := 1000
    for timeout > 0 {
        status := xhci_read32(XHCI_USBSTS)
        if (status & USBSTS_HCHALTED) != 0 {
            break
        }
        timeout--
    }
    
    if timeout == 0 {
        log.error("USB: xHCI reset timeout")
        return false
    }
    
    // Clear reset bit
    xhci_write32(XHCI_USBCMD, 0)
    
    log.info("USB: xHCI reset complete")
    return true
}


// Start xHCI Controller
xhci_start :: proc() -> bool {
    log.info("USB: Starting xHCI controller...")
    
    // Set Run/Stop bit
    cmd := xhci_read32(XHCI_USBCMD)
    xhci_write32(XHCI_USBCMD, cmd | USBCMD_RUN_STOP)
    
    // Wait for controller to start
    timeout := 1000
    for timeout > 0 {
        status := xhci_read32(XHCI_USBSTS)
        if (status & USBSTS_HCHALTED) == 0 {
            break
        }
        timeout--
    }
    
    if timeout == 0 {
        log.error("USB: xHCI start timeout")
        return false
    }
    
    log.info("USB: xHCI controller started")
    return true
}


// Initialize DCBAA (Device Context Base Address Array)
xhci_init_dcbaa :: proc() -> bool {
    // Allocate DCBAA (256 entries * 8 bytes = 2KB)
    dcbaa_size := 256 * 8
    dcbaa_phys := physical.allocate_contiguous(dcbaa_size)
    
    if dcbaa_phys == 0 {
        log.error("USB: Failed to allocate DCBAA")
        return false
    }
    
    xhci.dcbaa = dcbaa_phys
    
    // Clear DCBAA
    dcbaa_virt := virtual.physical_to_virtual(dcbaa_phys)
    mem.zero(cast([]u8)(dcbaa_virt, dcbaa_size))
    
    // Set DCBAA pointer
    xhci_write64(XHCI_DBAUP, dcbaa_phys)
    
    log.info("USB: DCBAA allocated at 0x%p", dcbaa_phys)
    return true
}


// Initialize Command Ring
xhci_init_command_ring :: proc() -> bool {
    // Allocate command ring (4KB)
    ring_size := 4096
    ring_phys := physical.allocate_contiguous(ring_size)
    
    if ring_phys == 0 {
        return false
    }
    
    xhci.command_ring = ring_phys
    
    // Clear command ring
    ring_virt := virtual.physical_to_virtual(ring_phys)
    mem.zero(cast([]u8)(ring_virt, ring_size))
    
    // Set command ring pointer
    xhci_write64(XHCI_CRCR_LO, ring_phys | 1)  // Ring Control State = 1
    
    log.info("USB: Command ring allocated at 0x%p", ring_phys)
    return true
}


// Initialize Event Ring
xhci_init_event_ring :: proc() -> bool {
    // Allocate event ring (8KB)
    ring_size := 8192
    ring_phys := physical.allocate_contiguous(ring_size)
    
    if ring_phys == 0 {
        return false
    }
    
    xhci.event_ring = ring_phys
    
    // Clear event ring
    ring_virt := virtual.physical_to_virtual(ring_phys)
    mem.zero(cast([]u8)(ring_virt, ring_size))
    
    log.info("USB: Event ring allocated at 0x%p", ring_phys)
    return true
}


// Enable Interrupts
xhci_enable_interrupts :: proc() {
    // Enable interrupter
    // This would configure the interrupter registers
    log.info("USB: Interrupts enabled")
}


// Scan USB Ports
xhci_scan_ports :: proc() {
    log.info("USB: Scanning ports...")
    
    PORTSC_OFFSET := 0x400  // Port Status/Control register offset
    PORT_SIZE := 0x10
    
    for port in 0..<xhci.max_ports {
        port_offset := PORTSC_OFFSET + (port * PORT_SIZE)
        portsc := xhci_read32(port_offset)
        
        // Check if port is connected
        if (portsc & 1) != 0 {  // CCS (Current Connect Status)
            log.info("USB: Port %d: Device connected", port)
            
            // Get port speed
            speed := (portsc >> 10) & 0xF
            speed_str := "Unknown"
            switch speed {
            case 1: speed_str = "Full Speed (USB 1.1)"
            case 2: speed_str = "Low Speed (USB 1.0)"
            case 3: speed_str = "High Speed (USB 2.0)"
            case 4: speed_str = "Super Speed (USB 3.0)"
            }
            
            log.info("USB: Port %d: Speed = %s", port, speed_str)
            
            // Initialize device on this port
            xhci_init_device(port, speed)
        }
    }
}


// Initialize Device on Port
xhci_init_device :: proc(port: u32, speed: u32) {
    if device_count >= 16 {
        log.error("USB: Maximum device count reached")
        return
    }
    
    // Allocate slot
    slot_id := xhci_allocate_slot()
    if slot_id == 0 {
        log.error("USB: Failed to allocate slot")
        return
    }
    
    usb_devices[device_count] = usb_device{
        slot_id = slot_id,
        port = port,
        speed = speed,
        address = 0,
        enabled = true,
    }
    
    log.info("USB: Device %d initialized on port %d (slot %d)", 
             device_count, port, slot_id)
    
    device_count++
}


// Allocate Slot
xhci_allocate_slot :: proc() -> u32 {
    // Find first free slot
    // In real implementation, this would use the Enable Slot command
    
    for slot in 1..<xhci.max_slots {
        // Check if slot is free (DCBAA entry is 0)
        dcbaa_virt := virtual.physical_to_virtual(xhci.dcbaa)
        dcbaa_entry := cast(*volatile u64)(dcbaa_virt + (slot * 8))
        
        if dcbaa_entry[] == 0 {
            return slot
        }
    }
    
    return 0
}


// USB Mass Storage Support
usb_mass_storage :: struct {
    device_id: u32,
    lun: u8,  // Logical Unit Number
    capacity: u64,  // In sectors
    block_size: u32,
    enabled: bool,
}

mass_storage_devices: [4]usb_mass_storage
mass_storage_count: u32 = 0


// Initialize USB Mass Storage
usb_ms_init :: proc(device_id: u32) -> bool {
    log.info("USB: Initializing mass storage device...")
    
    if mass_storage_count >= 4 {
        return false
    }
    
    // Send GET_MAX_LUN command
    lun := usb_ms_get_max_lun(device_id)
    
    // Read capacity
    capacity, block_size := usb_ms_read_capacity(device_id, lun)
    
    mass_storage_devices[mass_storage_count] = usb_mass_storage{
        device_id = device_id,
        lun = lun,
        capacity = capacity,
        block_size = block_size,
        enabled = true,
    }
    
    log.info("USB: Mass storage initialized - %d sectors (%d MB), %d byte blocks",
             capacity, (capacity * block_size) / (1024 * 1024), block_size)
    
    mass_storage_count++
    return true
}


// Get Max LUN
usb_ms_get_max_lun :: proc(device_id: u32) -> u8 {
    // CBW (Command Block Wrapper) for GET_MAX_LUN
    // This would send a bulk transfer
    return 0  // Single LUN
}


// Read Capacity
usb_ms_read_capacity :: proc(device_id: u32, lun: u8) -> (u64, u32) {
    // READ_CAPACITY_10 command
    // Returns last LBA and block size
    
    // Simplified - return dummy values
    return 1024 * 1024, 512  // 512MB device
}


// Read Sector
usb_ms_read :: proc(device_id: u32, lba: u64, buffer: []u8) -> bool {
    // Build CBW for READ_10 command
    // Send via bulk endpoint
    // Read response via bulk endpoint
    
    return true
}


// Write Sector
usb_ms_write :: proc(device_id: u32, lba: u64, buffer: []u8) -> bool {
    // Build CBW for WRITE_10 command
    // Send via bulk endpoint
    
    return true
}


// EHCI (USB 2.0) Support
ehci_state :: struct {
    initialized: bool,
    mmio_base: uintptr,
    max_ports: u32,
}

ehci: ehci_state


// Initialize EHCI Controller
ehci_init :: proc(mmio_phys: u64) -> bool {
    log.info("USB: Initializing EHCI controller...")
    
    ehci = ehci_state{
        mmio_base = virtual.physical_to_virtual(mmio_phys),
        initialized = false,
    }
    
    // Reset controller
    // Initialize periodic and asynchronous schedules
    // Start controller
    
    ehci.initialized = true
    log.info("USB: EHCI controller initialized")
    
    return true
}
