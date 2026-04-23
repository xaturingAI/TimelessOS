// Network Stack - TCP/IP Protocol Implementation
// Basic IPv4/TCP/UDP stack for TimelessOS

package drivers.network

import (
    "core:log"
    "core:mem"
    "mm:physical"
    "mm:virtual"
)

// ============================================================================
// Ethernet Frame Structures
// ============================================================================

// Ethernet Header (14 bytes)
ethernet_header :: struct {
    dest_mac:   [6]u8,
    src_mac:    [6]u8,
    ether_type: u16,
}

// Ethernet Frame Types
ETHER_TYPE_IP ::   0x0800  // IPv4
ETHER_TYPE_ARP ::  0x0806  // ARP
ETHER_TYPE_IP6 ::  0x86DD  // IPv6

// MAC Address Broadcast
MAC_BROADCAST :: [6]u8{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}


// ============================================================================
// ARP (Address Resolution Protocol)
// ============================================================================

// ARP Header
arp_header :: struct {
    hardware_type:      u16,
    protocol_type:      u16,
    hardware_size:      u8,
    protocol_size:      u8,
    opcode:             u16,
    sender_mac:         [6]u8,
    sender_ip:          [4]u8,
    target_mac:         [6]u8,
    target_ip:          [4]u8,
}

// ARP Hardware Types
ARP_HW_ETHERNET :: 1

// ARP Opcodes
ARP_REQUEST :: 1
ARP_REPLY ::   2

// ARP Cache Entry
arp_entry :: struct {
    ip:      [4]u8,
    mac:     [6]u8,
    timeout: u64,
    valid:   bool,
}

ARP_CACHE_SIZE :: 16
arp_cache: [ARP_CACHE_SIZE]arp_entry
arp_cache_count: u32


// ============================================================================
// IPv4 Header
// ============================================================================

ipv4_header :: struct {
    version_ihl:    u8,   // Version (4 bits) + IHL (4 bits)
    dscp_ecn:       u8,   // DSCP (6 bits) + ECN (2 bits)
    total_length:   u16,
    identification: u16,
    flags_fragment: u16,  // Flags (3 bits) + Fragment Offset (13 bits)
    ttl:            u8,
    protocol:       u8,
    checksum:       u16,
    src_ip:         [4]u8,
    dest_ip:        [4]u8,
    // Options follow if IHL > 5
}

// IP Protocol Numbers
IP_PROTO_ICMP :: 1
IP_PROTO_TCP ::  6
IP_PROTO_UDP ::  17

// IP Header Version
IP_VERSION :: 4
IP_IHL ::     5  // 5 * 4 = 20 bytes (no options)

// IP Flags
IP_DF :: (1 << 14)  // Don't Fragment
IP_MF :: (1 << 13)  // More Fragments


// ============================================================================
// ICMP (Internet Control Message Protocol)
// ============================================================================

icmp_header :: struct {
    type:     u8,
    code:     u8,
    checksum: u16,
    // Rest depends on type/code
}

// ICMP Types
ICMP_ECHO_REPLY ::   0
ICMP_DEST_UNREACH :: 3
ICMP_ECHO_REQUEST :: 8
ICMP_TIME_EXCEEDED :: 11

// ICMP Codes for Destination Unreachable
ICMP_NET_UNREACH ::   0
ICMP_HOST_UNREACH ::  1
ICMP_PORT_UNREACH ::  3


// ============================================================================
// TCP Header
// ============================================================================

tcp_header :: struct {
    src_port:    u16,
    dest_port:   u16,
    seq_num:     u32,
    ack_num:     u32,
    data_offset: u8,   // Data offset (4 bits) + Reserved (4 bits)
    flags:       u8,
    window:      u16,
    checksum:    u16,
    urgent_ptr:  u16,
    // Options follow if data_offset > 5
}

// TCP Flags
TCP_FIN :: (1 << 0)
TCP_SYN :: (1 << 1)
TCP_RST :: (1 << 2)
TCP_PSH :: (1 << 3)
TCP_ACK :: (1 << 4)
TCP_URG :: (1 << 5)

// TCP Connection State
tcp_state :: enum {
    Closed,
    Listen,
    Syn_Received,
    Syn_Sent,
    Established,
    Fin_Wait_1,
    Fin_Wait_2,
    Close_Wait,
    Closing,
    Last_Ack,
    Time_Wait,
}

// TCP Control Block
tcp_pcb :: struct {
    local_ip:    [4]u8,
    local_port:  u16,
    remote_ip:   [4]u8,
    remote_port: u16,
    state:       tcp_state,
    snd_nxt:     u32,  // Next sequence to send
    snd_una:     u32,  // Oldest unacknowledged sequence
    rcv_nxt:     u32,  // Next sequence to receive
    window:      u16,
    mss:         u16,  // Maximum Segment Size
    retransmit_timer: u64,
}

TCP_PCB_COUNT :: 32
tcp_pcbs: [TCP_PCB_COUNT]tcp_pcb


// ============================================================================
// UDP Header
// ============================================================================

udp_header :: struct {
    src_port:  u16,
    dest_port: u16,
    length:    u16,
    checksum:  u16,
}


// ============================================================================
// Network Interface Configuration
// ============================================================================

network_interface :: struct {
    name:       string,
    mac:        [6]u8,
    ip:         [4]u8,
    netmask:    [4]u8,
    gateway:    [4]u8,
    dns_server: [4]u8,
    mtu:        u16,
    flags:      u32,
    up:         bool,
}

// Interface Flags
IFF_UP ::       (1 << 0)
IFF_BROADCAST :: (1 << 1)
IFF_LOOPBACK ::  (1 << 3)

// Default Interface
default_interface: network_interface


// ============================================================================
// Network Buffer
// ============================================================================

net_buffer :: struct {
    data:       []u8,
    capacity:   u32,
    length:     u32,
    offset:     u32,
    next:       *net_buffer,
}

NET_BUFFER_SIZE :: 2048


// ============================================================================
// Network Stack Initialization
// ============================================================================

network_stack_init :: proc() -> bool {
    log.info("Network: Initializing TCP/IP stack...")
    
    // Clear ARP cache
    for i in 0..<ARP_CACHE_SIZE {
        arp_cache[i].valid = false
    }
    arp_cache_count = 0
    
    // Clear TCP PCBs
    for i in 0..<TCP_PCB_COUNT {
        tcp_pcbs[i].state = .Closed
    }
    
    // Initialize default interface
    default_interface = network_interface{
        name = "eth0",
        mac = e1000.mac_address,
        ip = [4]u8{0, 0, 0, 0},  // DHCP or static config
        netmask = [4]u8{255, 255, 255, 0},
        gateway = [4]u8{0, 0, 0, 0},
        mtu = 1500,
        flags = IFF_UP | IFF_BROADCAST,
        up = e1000.initialized && e1000.link_up,
    }
    
    log.info("Network: Stack initialized (MTU: %d)", default_interface.mtu)
    log.info("Network: MAC %02X:%02X:%02X:%02X:%02X:%02X",
             default_interface.mac[0], default_interface.mac[1],
             default_interface.mac[2], default_interface.mac[3],
             default_interface.mac[4], default_interface.mac[5])
    
    return true
}


// ============================================================================
// IP Address Utilities
// ============================================================================

ip_to_string :: proc(ip: [4]u8) -> string {
    // Format: "192.168.1.1"
    // Simplified - would need proper string formatting
    return ""
}

string_to_ip :: proc(s: string) -> [4]u8 {
    // Parse "192.168.1.1" to [4]u8
    return [4]u8{0, 0, 0, 0}
}

ip_is_broadcast :: proc(ip: [4]u8) -> bool {
    return ip == [4]u8{255, 255, 255, 255}
}

ip_is_same :: proc(a: [4]u8, b: [4]u8) -> bool {
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3]
}

ip_in_same_network :: proc(ip1: [4]u8, ip2: [4]u8, netmask: [4]u8) -> bool {
    return (ip1[0] & netmask[0]) == (ip2[0] & netmask[0]) &&
           (ip1[1] & netmask[1]) == (ip2[1] & netmask[1]) &&
           (ip1[2] & netmask[2]) == (ip2[2] & netmask[2]) &&
           (ip1[3] & netmask[3]) == (ip2[3] & netmask[3])
}


// ============================================================================
// Checksum Calculation
// ============================================================================

// Calculate IP checksum
ip_checksum :: proc(header: []u8) -> u16 {
    sum: u32 = 0
    
    // Sum all 16-bit words
    for i in 0..<len(header)/2 {
        word := u16(header[i*2]) | (u16(header[i*2+1]) << 8)
        sum += u32(word)
    }
    
    // Add carry bits
    while (sum >> 16) != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16)
    }
    
    // One's complement
    return cast(u16)(~sum)
}


// ============================================================================
// ARP Operations
// ============================================================================

// Send ARP Request
arp_request :: proc(target_ip: [4]u8) -> bool {
    if !e1000.initialized || !e1000.link_up {
        return false
    }
    
    log.debug("ARP: Request for %d.%d.%d.%d",
              target_ip[0], target_ip[1], target_ip[2], target_ip[3])
    
    // Build ARP packet
    var arp: arp_header
    arp.hardware_type = ARP_HW_ETHERNET
    arp.protocol_type = ETHER_TYPE_IP
    arp.hardware_size = 6
    arp.protocol_size = 4
    arp.opcode = ARP_REQUEST
    
    // Sender info
    for i in 0..<6 {
        arp.sender_mac[i] = e1000.mac_address[i]
    }
    for i in 0..<4 {
        arp.sender_ip[i] = default_interface.ip[i]
    }
    
    // Target info
    for i in 0..<6 {
        arp.target_mac[i] = 0
    }
    for i in 0..<4 {
        arp.target_ip[i] = target_ip[i]
    }
    
    // Build Ethernet frame
    var eth: ethernet_header
    for i in 0..<6 {
        eth.dest_mac[i] = 0xFF  // Broadcast
        eth.src_mac[i] = e1000.mac_address[i]
    }
    eth.ether_type = ETHER_TYPE_ARP
    
    // Serialize and transmit
    buffer_size := size_of(ethernet_header) + size_of(arp_header)
    buffer_phys := physical.allocate_contiguous(buffer_size)
    buffer_virt := virtual.physical_to_virtual(buffer_phys)
    
    data := cast([]u8)(buffer_virt, buffer_size)
    
    // Copy header
    mem.copy(data[0:size_of(ethernet_header)], 
             cast([]u8)(&eth, size_of(ethernet_header)))
    
    // Copy ARP
    mem.copy(data[size_of(ethernet_header):],
             cast([]u8)(&arp, size_of(arp_header)))
    
    return e1000_transmit(data)
}


// Process ARP Packet
arp_process :: proc(data: []u8) {
    if len(data) < size_of(arp_header) {
        return
    }
    
    arp := cast(*arp_header)(&data[0])
    
    if arp.opcode == ARP_REQUEST {
        // Check if request is for us
        if ip_is_same(arp.target_ip[:], default_interface.ip) {
            // Send ARP reply
            arp_send_reply(arp)
        }
    } else if arp.opcode == ARP_REPLY {
        // Update ARP cache
        arp_cache_add(arp.sender_ip[:], arp.sender_mac[:])
    }
}


// Send ARP Reply
arp_send_reply :: proc(request: *arp_header) -> bool {
    var arp: arp_header
    arp.hardware_type = ARP_HW_ETHERNET
    arp.protocol_type = ETHER_TYPE_IP
    arp.hardware_size = 6
    arp.protocol_size = 4
    arp.opcode = ARP_REPLY
    
    // Sender info (us)
    for i in 0..<6 {
        arp.sender_mac[i] = e1000.mac_address[i]
    }
    for i in 0..<4 {
        arp.sender_ip[i] = default_interface.ip[i]
    }
    
    // Target info (requester)
    for i in 0..<6 {
        arp.target_mac[i] = request.sender_mac[i]
    }
    for i in 0..<4 {
        arp.target_ip[i] = request.sender_ip[i]
    }
    
    // Build Ethernet frame (unicast to requester)
    var eth: ethernet_header
    for i in 0..<6 {
        eth.dest_mac[i] = request.sender_mac[i]
        eth.src_mac[i] = e1000.mac_address[i]
    }
    eth.ether_type = ETHER_TYPE_ARP
    
    // Serialize and transmit
    buffer_size := size_of(ethernet_header) + size_of(arp_header)
    buffer_phys := physical.allocate_contiguous(buffer_size)
    buffer_virt := virtual.physical_to_virtual(buffer_phys)
    
    data := cast([]u8)(buffer_virt, buffer_size)
    
    mem.copy(data[0:size_of(ethernet_header)], 
             cast([]u8)(&eth, size_of(ethernet_header)))
    mem.copy(data[size_of(ethernet_header):],
             cast([]u8)(&arp, size_of(arp_header)))
    
    return e1000_transmit(data)
}


// Add Entry to ARP Cache
arp_cache_add :: proc(ip: []u8, mac: []u8) {
    if len(ip) != 4 || len(mac) != 6 {
        return
    }
    
    // Check if entry exists
    for i in 0..<arp_cache_count {
        if ip_is_same(arp_cache[i].ip[:], cast([4]u8)(&ip[0])) {
            // Update existing
            for j in 0..<6 {
                arp_cache[i].mac[j] = mac[j]
            }
            arp_cache[i].valid = true
            return
        }
    }
    
    // Add new entry
    if arp_cache_count < ARP_CACHE_SIZE {
        idx := arp_cache_count
        for j in 0..<4 {
            arp_cache[idx].ip[j] = ip[j]
        }
        for j in 0..<6 {
            arp_cache[idx].mac[j] = mac[j]
        }
        arp_cache[idx].valid = true
        arp_cache_count++
    }
}


// Lookup MAC in ARP Cache
arp_cache_lookup :: proc(ip: [4]u8) -> *[6]u8 {
    for i in 0..<arp_cache_count {
        if arp_cache[i].valid && ip_is_same(arp_cache[i].ip, ip) {
            return &arp_cache[i].mac
        }
    }
    return nil
}


// ============================================================================
// IPv4 Packet Processing
// ============================================================================

// Send IPv4 Packet
ip_send :: proc(dest_ip: [4]u8, protocol: u8, payload: []u8) -> bool {
    if !default_interface.up {
        return false
    }
    
    // Check if destination is on local network
    if !ip_in_same_network(dest_ip, default_interface.ip, default_interface.netmask) {
        // Send to gateway
        dest_ip = default_interface.gateway
    }
    
    // Lookup MAC address
    mac := arp_cache_lookup(dest_ip)
    if mac == nil {
        // Need to ARP first
        if !arp_request(dest_ip) {
            return false
        }
        // Wait for ARP reply (simplified - would need proper async handling)
        return false
    }
    
    // Build IP header
    var ip: ipv4_header
    ip.version_ihl = (IP_VERSION << 4) | IP_IHL
    ip.total_length = cast(u16)(size_of(ipv4_header) + len(payload))
    ip.identification = 0  // Would increment
    ip.flags_fragment = IP_DF
    ip.ttl = 64
    ip.protocol = protocol
    ip.checksum = 0  // Calculated below
    for i in 0..<4 {
        ip.src_ip[i] = default_interface.ip[i]
        ip.dest_ip[i] = dest_ip[i]
    }
    
    // Calculate checksum
    header_bytes := cast([]u8)(&ip, size_of(ipv4_header))
    ip.checksum = ip_checksum(header_bytes)
    
    // Build Ethernet frame
    var eth: ethernet_header
    for i in 0..<6 {
        eth.dest_mac[i] = mac[]
        eth.src_mac[i] = e1000.mac_address[i]
    }
    eth.ether_type = ETHER_TYPE_IP
    
    // Serialize
    buffer_size := size_of(ethernet_header) + size_of(ipv4_header) + len(payload)
    buffer_phys := physical.allocate_contiguous(buffer_size)
    buffer_virt := virtual.physical_to_virtual(buffer_phys)
    
    data := cast([]u8)(buffer_virt, buffer_size)
    
    offset := 0
    mem.copy(data[offset:offset+size_of(ethernet_header)],
             cast([]u8)(&eth, size_of(ethernet_header)))
    offset += size_of(ethernet_header)
    
    mem.copy(data[offset:offset+size_of(ipv4_header)],
             cast([]u8)(&ip, size_of(ipv4_header)))
    offset += size_of(ipv4_header)
    
    mem.copy(data[offset:], payload)
    
    return e1000_transmit(data)
}


// Process Received IPv4 Packet
ip_process :: proc(data: []u8) {
    if len(data) < size_of(ipv4_header) {
        return
    }
    
    ip := cast(*ipv4_header)(&data[0])
    
    // Verify version
    if (ip.version_ihl >> 4) != IP_VERSION {
        return
    }
    
    // Verify checksum
    header_bytes := cast([]u8)(&ip[], size_of(ipv4_header))
    saved_checksum := ip.checksum
    ip.checksum = 0
    calc_checksum := ip_checksum(header_bytes)
    if calc_checksum != saved_checksum {
        log.warn("IP: Bad checksum")
        return
    }
    
    // Check destination
    if !ip_is_same(ip.dest_ip[:], default_interface.ip) &&
       !ip_is_broadcast(ip.dest_ip[:]) {
        return  // Not for us
    }
    
    // Process by protocol
    payload_offset := cast(u32)(ip.version_ihl & 0xF) * 4
    payload := data[payload_offset:]
    
    switch ip.protocol {
    case IP_PROTO_ICMP:
        icmp_process(payload)
    case IP_PROTO_TCP:
        tcp_process(ip.src_ip[:], ip.dest_ip[:], payload)
    case IP_PROTO_UDP:
        udp_process(ip.src_ip[:], ip.dest_ip[:], payload)
    case:
        log.debug("IP: Unknown protocol %d", ip.protocol)
    }
}


// ============================================================================
// ICMP Processing
// ============================================================================

// Send ICMP Echo Request (Ping)
icmp_echo_request :: proc(dest_ip: [4]u8) -> bool {
    var icmp: icmp_header
    icmp.type = ICMP_ECHO_REQUEST
    icmp.code = 0
    icmp.checksum = 0
    
    // Payload (simplified)
    payload_data := [8]u8{0, 0, 0, 0, 0, 0, 0, 0}
    
    // Calculate checksum
    icmp_bytes := cast([]u8)(&icmp, size_of(icmp_header))
    icmp.checksum = ip_checksum(icmp_bytes)
    
    payload := payload_data[:]
    return ip_send(dest_ip, IP_PROTO_ICMP, payload)
}


// Process ICMP Packet
icmp_process :: proc(data: []u8) {
    if len(data) < size_of(icmp_header) {
        return
    }
    
    icmp := cast(*icmp_header)(&data[0])
    
    switch icmp.type {
    case ICMP_ECHO_REQUEST:
        // Send echo reply
        icmp_echo_reply(icmp, data[size_of(icmp_header):])
    case ICMP_ECHO_REPLY:
        log.info("ICMP: Echo reply received")
    case ICMP_DEST_UNREACH:
        log.warn("ICMP: Destination unreachable (code %d)", icmp.code)
    case ICMP_TIME_EXCEEDED:
        log.warn("ICMP: Time exceeded")
    case:
        log.debug("ICMP: Unknown type %d", icmp.type)
    }
}


// Send ICMP Echo Reply
icmp_echo_reply :: proc(request: *icmp_header, payload: []u8) -> bool {
    var icmp: icmp_header
    icmp.type = ICMP_ECHO_REPLY
    icmp.code = 0
    icmp.checksum = 0
    
    // Calculate checksum with payload
    // Simplified - would need proper calculation
    
    return ip_send(request.src_ip[:], IP_PROTO_ICMP, payload)
}


// ============================================================================
// TCP Processing (Simplified Stub)
// ============================================================================

tcp_process :: proc(src_ip: []u8, dest_ip: []u8, data: []u8) {
    if len(data) < size_of(tcp_header) {
        return
    }
    
    tcp := cast(*tcp_header)(&data[0])
    
    log.debug("TCP: %d -> %d (flags: 0x%X)",
              tcp.src_port, tcp.dest_port, tcp.flags)
    
    // Find matching PCB
    pcb := tcp_find_pcb(dest_ip, tcp.dest_port[:], src_ip, tcp.src_port[:])
    
    if pcb == nil {
        // No matching connection
        if (tcp.flags & TCP_SYN) != 0 {
            // New connection attempt - would send RST or SYN-ACK if listening
        }
        return
    }
    
    // Process based on state and flags
    switch pcb.state {
    case .Listen:
        if (tcp.flags & TCP_SYN) != 0 {
            // SYN received - move to Syn_Received
            tcp_send_synack(pcb)
        }
    case .Syn_Sent:
        if (tcp.flags & TCP_SYN) != 0 && (tcp.flags & TCP_ACK) != 0 {
            // SYN-ACK received - connection established
            pcb.state = .Established
            tcp_send_ack(pcb)
        }
    case .Established:
        if (tcp.flags & TCP_FIN) != 0 {
            // Connection closing
            pcb.state = .Close_Wait
            tcp_send_ack(pcb)
        } else if (tcp.flags & TCP_RST) != 0 {
            // Connection reset
            pcb.state = .Closed
        }
    }
}


// Find TCP PCB
tcp_find_pcb :: proc(local_ip: []u8, local_port: []u8, 
                     remote_ip: []u8, remote_port: []u8) -> *tcp_pcb {
    for i in 0..<TCP_PCB_COUNT {
        if tcp_pcbs[i].state != .Closed {
            // Check if ports and IPs match
            // Simplified comparison
        }
    }
    return nil
}


// Send TCP SYN
tcp_send_syn :: proc(remote_ip: [4]u8, remote_port: u16) -> *tcp_pcb {
    // Find free PCB
    for i in 0..<TCP_PCB_COUNT {
        if tcp_pcbs[i].state == .Closed {
            pcb := &tcp_pcbs[i]
            pcb.state = .Syn_Sent
            pcb.remote_ip = remote_ip
            pcb.remote_port = remote_port
            pcb.local_port = 0  // Would assign ephemeral port
            pcb.snd_nxt = 0  // Would generate ISN
            pcb.snd_una = 0
            pcb.rcv_nxt = 0
            pcb.mss = 1460  // Standard MSS
            
            // Send SYN packet
            // tcp_send_segment(pcb, TCP_SYN, nil)
            
            return pcb
        }
    }
    return nil
}


// Send TCP SYN-ACK
tcp_send_synack :: proc(pcb: *tcp_pcb) {
    // Send SYN-ACK response
    // tcp_send_segment(pcb, TCP_SYN | TCP_ACK, nil)
}


// Send TCP ACK
tcp_send_ack :: proc(pcb: *tcp_pcb) {
    // Send ACK
    // tcp_send_segment(pcb, TCP_ACK, nil)
}


// ============================================================================
// UDP Processing (Simplified)
// ============================================================================

udp_process :: proc(src_ip: []u8, dest_ip: []u8, data: []u8) {
    if len(data) < size_of(udp_header) {
        return
    }
    
    udp := cast(*udp_header)(&data[0])
    
    log.debug("UDP: %d -> %d (length: %d)",
              udp.src_port, udp.dest_port, udp.length)
    
    // Process by port (DNS, DHCP, etc.)
    switch udp.dest_port {
    case 67, 68:
        // DHCP
        // dhcp_process(data[size_of(udp_header):])
    case 53:
        // DNS
        // dns_process(data[size_of(udp_header):])
    case:
        log.debug("UDP: Unknown port %d", udp.dest_port)
    }
}


// Send UDP Packet
udp_send :: proc(dest_ip: [4]u8, dest_port: u16, src_port: u16, payload: []u8) -> bool {
    var udp: udp_header
    udp.src_port = src_port
    udp.dest_port = dest_port
    udp.length = cast(u16)(size_of(udp_header) + len(payload))
    udp.checksum = 0  // Optional in IPv4
    
    return ip_send(dest_ip, IP_PROTO_UDP, 
                   cast([]u8)(&udp, size_of(udp_header))[:] ++ payload)
}


// ============================================================================
// Network Packet Reception
// ============================================================================

// Process Received Ethernet Frame
network_receive :: proc() {
    if !e1000.initialized || !e1000.link_up {
        return
    }
    
    // Allocate receive buffer
    buffer := [NET_BUFFER_SIZE]u8
    
    // Receive packet
    length := e1000_receive(buffer[:])
    
    if length == 0 {
        return  // No packet
    }
    
    if length < size_of(ethernet_header) {
        log.warn("Network: Packet too small (%d bytes)", length)
        return
    }
    
    // Parse Ethernet header
    eth := cast(*ethernet_header)(&buffer[0])
    
    // Check if packet is for us
    is_broadcast := true
    for i in 0..<6 {
        if eth.dest_mac[i] != 0xFF {
            is_broadcast = false
            break
        }
    }
    
    is_for_us := is_broadcast
    if !is_for_us {
        for i in 0..<6 {
            if eth.dest_mac[i] != e1000.mac_address[i] {
                is_for_us = false
                break
            }
            is_for_us = true
        }
    }
    
    if !is_for_us {
        return
    }
    
    // Process by EtherType
    payload := buffer[size_of(ethernet_header):length]
    
    switch eth.ether_type {
    case ETHER_TYPE_ARP:
        arp_process(payload)
    case ETHER_TYPE_IP:
        ip_process(payload)
    case:
        log.debug("Network: Unknown EtherType 0x%X", eth.ether_type)
    }
}


// ============================================================================
// Network Configuration
// ============================================================================

// Set Static IP
network_set_static :: proc(ip: [4]u8, netmask: [4]u8, gateway: [4]u8, dns: [4]u8) {
    default_interface.ip = ip
    default_interface.netmask = netmask
    default_interface.gateway = gateway
    default_interface.dns_server = dns
    default_interface.up = true
    
    log.info("Network: Static IP configured: %d.%d.%d.%d",
             ip[0], ip[1], ip[2], ip[3])
}


// DHCP Client (Stub)
network_dhcp :: proc() -> bool {
    log.info("Network: DHCP discovery...")
    
    // Send DHCP DISCOVER
    // Wait for DHCP OFFER
    // Send DHCP REQUEST
    // Wait for DHCP ACK
    
    // Simplified - would need full DHCP implementation
    network_set_static(
        [4]u8{192, 168, 1, 100},
        [4]u8{255, 255, 255, 0},
        [4]u8{192, 168, 1, 1},
        [4]u8{192, 168, 1, 1}
    )
    
    return true
}
