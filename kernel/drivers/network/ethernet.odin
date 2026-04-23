// Network Drivers - Intel e1000/e1000e and VirtIO-Net
// Ethernet controller drivers for TimelessOS

package drivers.network

import (
    "core:log"
    "core:mem"
    "mm:physical"
    "mm:virtual"
)

// ============================================================================
// Intel e1000/e1000e Driver
// ============================================================================

// e1000 Register Offsets
E1000_CTRL ::      0x0000  // Device Control
E1000_STATUS ::    0x0008  // Device Status
E1000_EECD ::      0x0010  // EEPROM/Flash Control
E1000_EERD ::      0x0014  // EEPROM Read
E1000_INTERRUPT :: 0x00C0  // Interrupt Control
E1000_RCTL ::      0x0100  // Receive Control
E1000_TCTL ::      0x0400  // Transmit Control
E1000_RDBAL ::     0x2800  // Receive Descriptor Base Low
E1000_RDBAH ::     0x2804  // Receive Descriptor Base High
E1000_RDLEN ::     0x2808  // Receive Descriptor Length
E1000_RDH ::       0x2810  // Receive Descriptor Head
E1000_RDT ::       0x2818  // Receive Descriptor Tail
E1000_TDBAL ::     0x3800  // Transmit Descriptor Base Low
E1000_TDBAH ::     0x3804  // Transmit Descriptor Base High
E1000_TDLEN ::     0x3808  // Transmit Descriptor Length
E1000_TDH ::       0x3810  // Transmit Descriptor Head
E1000_TDT ::       0x3818  // Transmit Descriptor Tail
E1000_MTA ::       0x5200  // Multicast Table Array
E1000_RAL ::       0x5400  // Receive Address Low
E1000_RAH ::       0x5404  // Receive Address High

// Device Control Bits
CTRL_SLU ::     (1 << 6)   // Set Link Up
CTRL_ASDE ::    (1 << 5)   // Auto Speed Detection Enable
CTRL_FRCSPD ::  (1 << 11)  // Force Speed
CTRL_FRCDPX ::  (1 << 12)  // Force Duplex
CTRL_RST ::     (1 << 26)  // Device Reset

// Device Status Bits
STATUS_LU ::    (1 << 1)   // Link Up
STATUS_FD ::    (1 << 0)   // Full Duplex
STATUS_SPEED :: 0xC0       // Speed mask (bits 6-7)

// Receive Control Bits
RCTL_EN ::      (1 << 1)   // Receiver Enable
RCTL_SBP ::     (1 << 2)   // Store Bad Packets
RCTL_UPE ::     (1 << 3)   // Unicast Promiscuous Enable
RCTL_MPE ::     (1 << 4)   // Multicast Promiscuous Enable
RCTL_LPE ::     (1 << 5)   // Long Packet Reception Enable
RCTL_LBM_NONE :: 0         // No Loopback
RCTL_LBM_MAC :: (1 << 6)   // MAC Loopback
RCTL_RDMTS_HALF :: 0       // RX Buffer Min Threshold Size
RCTL_MO_36 ::   (3 << 12)  // Multicast Offset
RCTL_BAM ::     (1 << 15)  // Broadcast Accept Mode
RCTL_SZ_2048 :: (3 << 16)  // RX Buffer Size 2048 bytes
RCTL_SECRC ::   (1 << 26)  // Strip Ethernet CRC

// Transmit Control Bits
TCTL_EN ::      (1 << 1)   // Transmitter Enable
TCTL_PSP ::     (1 << 3)   // Pad Short Packets
TCTL_CT ::      (0x3F << 4) // Collision Threshold
TCTL_RTLC ::    (1 << 24)  // Re-transmit on Late Collision

// Interrupt Bits
IMS_TXDW ::     (1 << 0)   // Transmit Descriptor Written Back
IMS_LSC ::      (1 << 2)   // Link Status Change
IMS_RXSEQ ::    (1 << 3)   // Receive Sequence Error
IMS_RXDMT0 ::   (1 << 4)   // RX Descriptor Min Threshold
IMS_RXO ::      (1 << 6)   // Receiver Overrun
IMS_RXT0 ::     (1 << 7)   // Receiver Timer Interrupt

// e1000 State
e1000_state :: struct {
    initialized: bool,
    mmio_base: uintptr,
    mac_address: [6]u8,
    rx_ring_phys: u64,
    rx_ring_virt: uintptr,
    rx_ring_size: u32,
    rx_ring_head: u32,
    rx_ring_tail: u32,
    tx_ring_phys: u64,
    tx_ring_virt: uintptr,
    tx_ring_size: u32,
    tx_ring_head: u32,
    tx_ring_tail: u32,
    link_up: bool,
    link_speed: u32,
    link_duplex: bool,
}

e1000: e1000_state

// Descriptor Constants
E1000_RXD_LEN :: 128  // RX descriptor length in bytes
E1000_TXD_LEN :: 128  // TX descriptor length in bytes
RX_BUFFER_SIZE :: 2048
TX_BUFFER_SIZE :: 1536  // Max Ethernet frame


// Receive Descriptor
e1000_rx_desc :: struct {
    buffer_addr: u64,
    length: u16,
    checksum: u16,
    status: u8,
    errors: u8,
    special: u16,
}

// Transmit Descriptor
e1000_tx_desc :: struct {
    buffer_addr: u64,
    length: u16,
    cso: u8,
    cmd: u8,
    status: u8,
    css: u8,
    special: u16,
}

// TX Command Bits
TXD_CMD_EOP ::   (1 << 0)  // End of Packet
TXD_CMD_IFCS ::  (1 << 1)  // Insert FCS
TXD_CMD_IC ::    (1 << 2)  // Insert Checksum
TXD_CMD_RS ::    (1 << 3)  // Report Status
TXD_CMD_RPS ::   (1 << 4)  // Report Packet Sent
TXD_CMD_DEXT ::  (1 << 5)  // Descriptor Extension
TXD_CMD_VLE ::   (1 << 6)  // VLAN Packet Enable
TXD_CMD_IDE ::   (1 << 7)  // Interrupt Delay Enable


// Initialize e1000 Device
e1000_init :: proc(mmio_phys: u64) -> bool {
    log.info("Network: Initializing Intel e1000...")
    
    e1000 = e1000_state{
        mmio_base = virtual.physical_to_virtual(mmio_phys),
        initialized = false,
    }
    
    // Reset device
    if !e1000_reset() {
        log.error("Network: e1000 reset failed")
        return false
    }
    
    // Read MAC address from EEPROM
    if !e1000_read_mac() {
        log.error("Network: e1000 failed to read MAC")
        return false
    }
    
    log.info("Network: e1000 MAC: %02X:%02X:%02X:%02X:%02X:%02X",
             e1000.mac_address[0], e1000.mac_address[1],
             e1000.mac_address[2], e1000.mac_address[3],
             e1000.mac_address[4], e1000.mac_address[5])
    
    // Initialize receive ring
    if !e1000_init_rx() {
        log.error("Network: e1000 RX initialization failed")
        return false
    }
    
    // Initialize transmit ring
    if !e1000_init_tx() {
        log.error("Network: e1000 TX initialization failed")
        return false
    }
    
    // Configure interrupts
    e1000_setup_interrupts()
    
    // Enable receiver and transmitter
    e1000_enable_rx_tx()
    
    // Check link status
    e1000_check_link()
    
    e1000.initialized = true
    log.info("Network: e1000 initialized")
    
    return true
}


// e1000 MMIO Access
e1000_read32 :: proc(offset: u32) -> u32 {
    ptr := cast(*volatile u32)(e1000.mmio_base + offset)
    return ptr[]
}

e1000_write32 :: proc(offset: u32, value: u32) {
    ptr := cast(*volatile u32)(e1000.mmio_base + offset)
    ptr[] = value
}

e1000_read_array :: proc(offset: u32, index: u32) -> u32 {
    return e1000_read32(offset + (index * 4))
}

e1000_write_array :: proc(offset: u32, index: u32, value: u32) {
    e1000_write32(offset + (index * 4), value)
}


// Reset e1000 Device
e1000_reset :: proc() -> bool {
    log.info("Network: Resetting e1000...")
    
    // Set reset bit
    ctrl := e1000_read32(E1000_CTRL)
    e1000_write32(E1000_CTRL, ctrl | CTRL_RST)
    
    // Wait for reset to complete
    timeout := 1000
    for timeout > 0 {
        status := e1000_read32(E1000_STATUS)
        if (status & STATUS_LU) == 0 {
            break
        }
        timeout--
    }
    
    // Clear reset bit
    ctrl = e1000_read32(E1000_CTRL)
    e1000_write32(E1000_CTRL, ctrl & ~u32(CTRL_RST))
    
    // Wait for EEPROM auto-read to complete
    timeout = 1000
    for timeout > 0 {
        eecd := e1000_read32(E1000_EECD)
        if (eecd & (1 << 9)) != 0 {  // EEPROM Auto-Read Done
            break
        }
        timeout--
    }
    
    if timeout == 0 {
        log.error("Network: e1000 EEPROM read timeout")
        return false
    }
    
    log.info("Network: e1000 reset complete")
    return true
}


// Read MAC Address from EEPROM
e1000_read_mac :: proc() -> bool {
    // MAC address is stored in EEPROM words 0-2
    word0 := e1000_eeprom_read(0)
    word1 := e1000_eeprom_read(1)
    word2 := e1000_eeprom_read(2)
    
    if word0 == 0xFFFF && word1 == 0xFFFF && word2 == 0xFFFF {
        log.error("Network: e1000 invalid EEPROM")
        return false
    }
    
    // EEPROM stores MAC in little-endian word format
    e1000.mac_address[0] = cast(u8)(word0)
    e1000.mac_address[1] = cast(u8)(word0 >> 8)
    e1000.mac_address[2] = cast(u8)(word1)
    e1000.mac_address[3] = cast(u8)(word1 >> 8)
    e1000.mac_address[4] = cast(u8)(word2)
    e1000.mac_address[5] = cast(u8)(word2 >> 8)
    
    return true
}


// Read EEPROM Word
e1000_eeprom_read :: proc(offset: u32) -> u16 {
    EERD_START :: (1 << 4)
    EERD_DONE ::  (1 << 16)
    
    // Start EEPROM read
    e1000_write32(E1000_EERD, EERD_START | (offset << 8))
    
    // Wait for read to complete
    timeout := 1000
    for timeout > 0 {
        eerd := e1000_read32(E1000_EERD)
        if (eerd & EERD_DONE) != 0 {
            return cast(u16)(eerd >> 16)
        }
        timeout--
    }
    
    return 0xFFFF
}


// Initialize Receive Ring
e1000_init_rx :: proc() -> bool {
    // Allocate receive descriptor ring
    ring_size := E1000_RXD_LEN * 8  // 8 descriptors
    ring_phys := physical.allocate_contiguous(ring_size)
    
    if ring_phys == 0 {
        return false
    }
    
    e1000.rx_ring_phys = ring_phys
    e1000.rx_ring_virt = virtual.physical_to_virtual(ring_phys)
    e1000.rx_ring_size = 8
    
    mem.zero(cast([]u8)(e1000.rx_ring_virt, ring_size))
    
    // Allocate receive buffers
    for i in 0..<e1000.rx_ring_size {
        buffer_phys := physical.allocate_contiguous(RX_BUFFER_SIZE)
        if buffer_phys == 0 {
            return false
        }
        
        desc := cast(*e1000_rx_desc)(e1000.rx_ring_virt + (i * 16))
        desc.buffer_addr = buffer_phys
    }
    
    // Configure receive ring
    e1000_write32(E1000_RDBAL, u32(ring_phys))
    e1000_write32(E1000_RDBAH, u32(ring_phys >> 32))
    e1000_write32(E1000_RDLEN, ring_size)
    e1000_write32(E1000_RDH, 0)
    e1000_write32(E1000_RDT, e1000.rx_ring_size - 1)
    
    // Configure receive control
    rctl := RCTL_EN | RCTL_SBP | RCTL_UPE | RCTL_MPE |
            RCTL_LBM_NONE | RCTL_RDMTS_HALF | RCTL_MO_36 |
            RCTL_BAM | RCTL_SZ_2048 | RCTL_SECRC
    
    e1000_write32(E1000_RCTL, rctl)
    
    log.info("Network: e1000 RX ring initialized (%d descriptors)", 
             e1000.rx_ring_size)
    
    return true
}


// Initialize Transmit Ring
e1000_init_tx :: proc() -> bool {
    // Allocate transmit descriptor ring
    ring_size := E1000_TXD_LEN * 8  // 8 descriptors
    ring_phys := physical.allocate_contiguous(ring_size)
    
    if ring_phys == 0 {
        return false
    }
    
    e1000.tx_ring_phys = ring_phys
    e1000.tx_ring_virt = virtual.physical_to_virtual(ring_phys)
    e1000.tx_ring_size = 8
    
    mem.zero(cast([]u8)(e1000.tx_ring_virt, ring_size))
    
    // Configure transmit ring
    e1000_write32(E1000_TDBAL, u32(ring_phys))
    e1000_write32(E1000_TDBAH, u32(ring_phys >> 32))
    e1000_write32(E1000_TDLEN, ring_size)
    e1000_write32(E1000_TDH, 0)
    e1000_write32(E1000_TDT, 0)
    
    // Configure transmit control
    tctl := TCTL_EN | TCTL_PSP | TCTL_CT | TCTL_RTLC
    
    e1000_write32(E1000_TCTL, tctl)
    
    // Set transmit IPG (Inter-Packet Gap)
    e1000_write32(0x0410, 0x0060200A)  // Default IPG value
    
    log.info("Network: e1000 TX ring initialized (%d descriptors)", 
             e1000.tx_ring_size)
    
    return true
}


// Setup Interrupts
e1000_setup_interrupts :: proc() {
    // Enable interrupts
    ims := IMS_TXDW | IMS_LSC | IMS_RXSEQ | IMS_RXDMT0 | IMS_RXO | IMS_RXT0
    e1000_write32(E1000_INTERRUPT, ims)
    
    // Clear any pending interrupts
    e1000_read32(E1000_INTERRUPT)
    
    log.info("Network: e1000 interrupts configured")
}


// Enable Receiver and Transmitter
e1000_enable_rx_tx :: proc() {
    // Set link up
    ctrl := e1000_read32(E1000_CTRL)
    e1000_write32(E1000_CTRL, ctrl | CTRL_SLU | CTRL_ASDE)
    
    // Receiver and transmitter are enabled in init_rx/tx
    log.info("Network: e1000 RX/TX enabled")
}


// Check Link Status
e1000_check_link :: proc() {
    status := e1000_read32(E1000_STATUS)
    
    e1000.link_up = (status & STATUS_LU) != 0
    
    if e1000.link_up {
        // Get speed
        speed_bits := (status & STATUS_SPEED) >> 6
        switch speed_bits {
        case 0: e1000.link_speed = 10
        case 1: e1000.link_speed = 100
        case 2: e1000.link_speed = 1000
        case: e1000.link_speed = 0
        }
        
        e1000.link_duplex = (status & STATUS_FD) != 0
        
        log.info("Network: e1000 link up - %d Mbps, %s duplex",
                 e1000.link_speed, 
                 if e1000.link_duplex then "full" else "half")
    } else {
        log.info("Network: e1000 link down")
    }
}


// Transmit Packet
e1000_transmit :: proc(data: []u8) -> bool {
    if !e1000.initialized || !e1000.link_up {
        return false
    }
    
    // Wait for free descriptor
    if e1000.tx_ring_head >= e1000.tx_ring_size {
        // Ring full - wait or drop
        return false
    }
    
    // Allocate transmit buffer
    buffer_phys := physical.allocate_contiguous(len(data))
    buffer_virt := virtual.physical_to_virtual(buffer_phys)
    
    // Copy data to buffer
    mem.copy(cast([]u8)(buffer_virt, len(data)), data)
    
    // Setup transmit descriptor
    desc := cast(*e1000_tx_desc)(e1000.tx_ring_virt + (e1000.tx_ring_head * 16))
    desc.buffer_addr = buffer_phys
    desc.length = cast(u16)(len(data))
    desc.cmd = TXD_CMD_EOP | TXD_CMD_IFCS | TXD_CMD_RS
    desc.status = 0
    
    // Advance head
    e1000.tx_ring_head++
    
    // Notify hardware
    e1000_write32(E1000_TDT, e1000.tx_ring_head)
    
    return true
}


// Receive Packet
e1000_receive :: proc(buffer: []u8) -> int {
    if !e1000.initialized || !e1000.link_up {
        return 0
    }
    
    // Check for received packets
    desc := cast(*e1000_rx_desc)(e1000.rx_ring_virt + (e1000.rx_ring_head * 16))
    
    if (desc.status & 1) == 0 {  // DD (Descriptor Done) bit
        return 0  // No packet
    }
    
    // Get packet length
    length := desc.length
    
    if length > len(buffer) {
        length = len(buffer)
    }
    
    // Copy data from receive buffer
    buffer_phys := desc.buffer_addr
    buffer_virt := virtual.physical_to_virtual(buffer_phys)
    mem.copy(buffer, cast([]u8)(buffer_virt, length))
    
    // Return buffer to ring
    desc.status = 0
    
    // Advance head
    e1000.rx_ring_head = (e1000.rx_ring_head + 1) % e1000.rx_ring_size
    
    // Update tail
    e1000_write32(E1000_RDT, e1000.rx_ring_head)
    
    return length
}


// ============================================================================
// Network Interrupt Handler
// ============================================================================

// Handle e1000 Interrupt
e1000_interrupt_handler :: proc() {
    // Read interrupt status
    status := e1000_read32(E1000_INTERRUPT)
    
    // Link Status Change
    if (status & IMS_LSC) != 0 {
        e1000_check_link()
    }
    
    // Receive Packet
    if (status & IMS_RXDMT0) != 0 || (status & IMS_RXT0) != 0 {
        // Process received packets
        for _ in 0..<16 {  // Process up to 16 packets
            network_receive()
        }
    }
    
    // Transmit Complete
    if (status & IMS_TXDW) != 0 {
        // Free transmitted buffers
        // Would walk TX ring and free buffers
    }
    
    // Clear interrupt
    e1000_read32(E1000_INTERRUPT)
}


// ============================================================================
// VirtIO-Net Driver
// ============================================================================

// VirtIO-Net Configuration
VIRTIO_NET_CONFIG :: struct {
    mac: [6]u8,
    status: u16,
    max_virtqueue_pairs: u16,
    mtu: u16,
}

// VirtIO-Net Features
VIRTIO_NET_F_MAC ::         5
VIRTIO_NET_F_STATUS ::      16
VIRTIO_NET_F_CTRL_VQ ::     17
VIRTIO_NET_F_MQ ::          22

// VirtIO-Net Header
virtio_net_hdr :: struct {
    flags: u8,
    gso_type: u8,
    hdr_len: u16,
    gso_size: u16,
    csum_start: u16,
    csum_offset: u16,
    num_buffers: u16,
}

// VirtIO-Net State
virtio_net_state :: struct {
    initialized: bool,
    mmio_base: uintptr,
    mac_address: [6]u8,
    rx_queue: u64,
    tx_queue: u64,
    mtu: u16,
    link_up: bool,
}

virtio_net: virtio_net_state


// Initialize VirtIO-Net
virtio_net_init :: proc(mmio_phys: u64) -> bool {
    log.info("Network: Initializing VirtIO-Net...")
    
    virtio_net = virtio_net_state{
        mmio_base = virtual.physical_to_virtual(mmio_phys),
        initialized = false,
    }
    
    // Verify VirtIO device
    magic := virtio_net_read32(0x000)
    if magic != 0x74726976 {  // "virt"
        return false
    }
    
    device_id := virtio_net_read32(0x008)
    if device_id != 1 {  // VirtIO Network device
        return false
    }
    
    // Reset device
    virtio_net_write32(0x070, 0)
    
    // Acknowledge
    virtio_net_write32(0x070, 1)
    
    // Driver
    virtio_net_write32(0x070, 3)
    
    // Read features
    features := virtio_net_read32(0x010)
    
    // Driver features
    virtio_net_write32(0x020, 0)
    
    // Features OK
    virtio_net_write32(0x070, 7)
    
    // Setup queues
    // rx_queue = setup_virtqueue(0)
    // tx_queue = setup_virtqueue(1)
    
    // Read config
    // mac := read_config(0, 6)
    
    virtio_net.initialized = true
    log.info("Network: VirtIO-Net initialized")
    
    return true
}


// VirtIO MMIO Access
virtio_net_read32 :: proc(offset: u32) -> u32 {
    ptr := cast(*volatile u32)(virtio_net.mmio_base + offset)
    return ptr[]
}

virtio_net_write32 :: proc(offset: u32, value: u32) {
    ptr := cast(*volatile u32)(virtio_net.mmio_base + offset)
    ptr[] = value
}


// VirtIO-Net Transmit
virtio_net_transmit :: proc(data: []u8) -> bool {
    if !virtio_net.initialized {
        return false
    }
    
    // Add to TX queue
    // Notify device
    
    return true
}


// VirtIO-Net Receive
virtio_net_receive :: proc(buffer: []u8) -> int {
    if !virtio_net.initialized {
        return 0
    }
    
    // Check RX queue
    // Return packet length
    
    return 0
}
