# TimelessOS Quick Reference Guide

**For Developers and Contributors**

---

## Current Status (v0.1.0 - Pre-Alpha)

### ✅ What Works Now
- Boots on x86_64 UEFI systems
- Physical and virtual memory management
- Interrupt handling (IDT, PIC, APIC)
- Basic console output (VGA, serial)
- Keyboard and mouse input
- GPU drivers (Intel, AMD, NVIDIA, VirtIO framework)
- VFS (Virtual Filesystem Layer)
- FAT32, ext4, XFS (mount only), ZFS (stub)
- Network drivers (e1000, VirtIO-Net)
- TCP/IP stack (basic ARP, IP, ICMP, TCP/UDP stubs)
- Service manager (dinit)

### 🔄 In Progress
- Complete filesystem implementations (FAT32, ext4, XFS)
- Full TCP/IP stack
- Process and thread management
- Scheduler

### ⏳ Not Yet Implemented
- User mode execution (Ring 3)
- System calls
- Userspace environment
- USB support
- Advanced power management
- Security features

---

## Building TimelessOS

### Prerequisites
```bash
# Odin compiler
git clone https://github.com/odin-lang/Odin
cd Odin && ./build.sh

# QEMU for testing
sudo apt install qemu-system-x86 ovmf  # Linux
brew install qemu  # macOS
```

### Build Commands
```bash
cd System/timeless-os
./build/build.sh

# Output: TimelessOS.bin (UEFI application)
```

### Run in QEMU
```bash
# Basic boot
qemu-system-x86_64 \
  -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
  -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd \
  -kernel TimelessOS.bin \
  -serial stdio

# With networking
qemu-system-x86_64 \
  -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
  -kernel TimelessOS.bin \
  -device e1000,netdev=net0 \
  -netdev user,id=net0 \
  -serial stdio

# With filesystems
qemu-system-x86_64 \
  -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
  -kernel TimelessOS.bin \
  -drive file=fat32.img,format=raw \
  -drive file=ext4.img,format=raw \
  -device e1000,netdev=net0 \
  -netdev user,id=net0 \
  -serial stdio
```

---

## Project Structure

```
System/timeless-os/
├── kernel/                      # Kernel source
│   ├── main.odin                # Entry point
│   ├── arch/x86_64/             # Architecture code
│   ├── mm/                      # Memory management
│   ├── interrupts/              # Interrupt handling
│   ├── drivers/                 # Device drivers
│   ├── filesystem/              # Filesystem drivers
│   └── services/                # Kernel services
├── build/                       # Build scripts
├── tools/                       # Build tools
└── docs/                        # Documentation
```

---

## Key Files to Know

| File | Purpose |
|------|---------|
| `kernel/main.odin` | Kernel entry point, initialization |
| `kernel/mm/physical.odin` | Physical memory allocator |
| `kernel/mm/virtual.odin` | Virtual memory, page tables |
| `kernel/mm/heap.odin` | Kernel heap allocator |
| `kernel/interrupts/apic.odin` | APIC interrupt controller |
| `kernel/drivers/network/ethernet.odin` | e1000/VirtIO-Net drivers |
| `kernel/drivers/network/stack.odin` | TCP/IP stack |
| `kernel/filesystem/vfs.odin` | Virtual filesystem layer |
| `kernel/filesystem/fat32.odin` | FAT32 driver |
| `kernel/filesystem/ext4.odin` | ext4 driver |
| `kernel/filesystem/xfs.odin` | XFS driver |
| `docs/ROADMAP.md` | Complete development roadmap |
| `docs/TASK_BREAKDOWN.md` | Detailed task list |
| `docs/ZFS_PORTING_PLAN.md` | ZFS implementation plan |

---

## Network Stack Quick Start

### Initialize Network
```odin
// In kernel code:
import "drivers:network"

// Initialize stack
if !drivers.network.network_stack_init() {
    log.error("Network init failed")
}

// Configure static IP
drivers.network.network_set_static(
    [4]u8{192, 168, 1, 100},  // IP
    [4]u8{255, 255, 255, 0},  // Netmask
    [4]u8{192, 168, 1, 1},    // Gateway
    [4]u8{192, 168, 1, 1}     // DNS
)

// Or use DHCP
drivers.network.network_dhcp()
```

### Send Ping
```odin
import "drivers:network"

// Send ICMP echo request
dest_ip := [4]u8{8, 8, 8, 8}  // Google DNS
drivers.network.icmp_echo_request(dest_ip)
```

---

## Filesystem Quick Start

### Mount Filesystem
```odin
import "filesystem:vfs"

// Mount FAT32 EFI partition
vfs.vfs_mount("/dev/sda1", "/boot", "fat32", 0)

// Mount ext4 root
vfs.vfs_mount("/dev/sda2", "/", "ext4", 0)

// Mount XFS data
vfs.vfs_mount("/dev/sdb1", "/data", "xfs", 0)
```

### File Operations
```odin
// Open file
file := vfs.vfs_open("/etc/config.txt", vfs.O_RDONLY, 0)

// Read file
buffer := [1024]u8
n := vfs.vfs_read(file, buffer[:])

// Close file
vfs.vfs_close(file)
```

---

## Common Constants

### Network
```odin
ETHER_TYPE_IP ::   0x0800
ETHER_TYPE_ARP ::  0x0806
IP_PROTO_ICMP ::   1
IP_PROTO_TCP ::    6
IP_PROTO_UDP ::    17
```

### Filesystem Flags
```odin
// Mount flags
MOUNT_RDONLY ::  1
MOUNT_NOEXEC ::   2
MOUNT_NOSUID ::   4

// Open flags
O_RDONLY ::  0
O_WRONLY ::  1
O_RDWR ::    2
O_CREAT ::   4
O_TRUNC ::   16
O_APPEND ::  32
```

### Filesystem Magic Numbers
```odin
EXT4_MAGIC :: 0xEF53
XFS_MAGIC ::  0x58465342  // "XFSB"
```

---

## Development Workflow

### 1. Make Changes
```bash
cd System/timeless-os
# Edit files in kernel/
```

### 2. Build
```bash
./build/build.sh
```

### 3. Test in QEMU
```bash
qemu-system-x86_64 \
  -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
  -kernel TimelessOS.bin \
  -serial stdio
```

### 4. Debug
```bash
# Enable debug logging
# In kernel code, set:
log.set_level(.DEBUG)

# Or use QEMU debug
qemu-system-x86_64 ... -d int,cpu_reset -D qemu.log
```

---

## Debugging Tips

### Serial Console
```odin
// Output to serial console
log.info("Debug message: %d", value)
log.debug("Variable: %p", ptr)
log.error("Error: %s", message)
```

### QEMU Debugging
```bash
# Enable GDB server
qemu-system-x86_64 ... -s -S

# Connect GDB
gdb TimelessOS.elf
(gdb) target remote :1234
(gdb) continue
```

### Common Issues

**Triple Fault (Boot Loop)**
- Check IDT setup
- Verify GDT entries
- Check TSS configuration

**Memory Corruption**
- Check physical allocator
- Verify page table mappings
- Look for buffer overflows

**Interrupts Not Working**
- Verify APIC initialization
- Check IRQ routing
- Ensure interrupts are enabled (STI)

---

## Testing Checklist

Before submitting code:

- [ ] Code compiles without warnings
- [ ] Boots in QEMU
- [ ] No memory leaks (if applicable)
- [ ] No obvious race conditions
- [ ] Follows existing code style
- [ ] Updated documentation
- [ ] Added tests (if applicable)

---

## Getting Help

### Documentation
- `docs/ROADMAP.md` - Development plan
- `docs/TASK_BREAKDOWN.md` - Task details
- `docs/NETWORK_FILESYSTEMS_IMPLEMENTATION.md` - Network/FS guide
- `docs/ZFS_PORTING_PLAN.md` - ZFS planning

### External Resources
- OSDev Wiki: https://wiki.osdev.org
- Intel SDM: https://www.intel.com/sdm
- UEFI Spec: https://uefi.org/specifications
- Odin Docs: https://odin-lang.org/docs

---

## Contributing

### Good First Tasks
1. Fix TODO comments in existing code
2. Add logging to untested code paths
3. Write tests for existing functionality
4. Improve documentation
5. Add simple drivers (HPET, RTC)
6. Port Unix utilities

### Code Review Guidelines
- Keep changes small and focused
- Write clear commit messages
- Test thoroughly before submitting
- Follow existing code style
- Document new APIs

---

## Version History

| Version | Date | Status | Key Features |
|---------|------|--------|--------------|
| 0.1.0 | 2026-04-22 | Pre-Alpha | Foundation, basic drivers, VFS, network stub |

---

## Roadmap Summary

| Phase | Timeline | Goal |
|-------|----------|------|
| Phase 1 | Months 1-6 | ✅ Foundation (current) |
| Phase 2 | Months 7-12 | Core kernel (process, scheduler) |
| Phase 3 | Months 13-18 | User mode execution |
| Phase 4 | Months 19-30 | Userspace environment |
| Phase 5 | Months 31-42 | Advanced features |
| Phase 6 | Months 43-54 | Production hardening |

**Target 1.0 Release:** Month 42 (Q1 2030)

---

## Quick Commands Reference

### Build & Run
```bash
./build/build.sh                    # Build kernel
qemu-system-x86_64 -kernel ...      # Run in QEMU
```

### Create Test Images
```bash
dd if=/dev/zero of=test.img bs=1M count=512
mkfs.fat -F 32 test.img             # FAT32
mkfs.ext4 test.img                  # ext4
mkfs.xfs test.img                   # XFS
```

### Debug
```bash
qemu-system-x86_64 ... -s -S        # GDB server
gdb TimelessOS.elf                  # Connect debugger
```

---

**Last Updated:** April 22, 2026  
**Version:** 0.1.0  
**Maintainer:** TimelessOS Development Team
