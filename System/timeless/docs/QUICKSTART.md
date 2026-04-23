# TimelessOS Quick Start Guide

## Prerequisites Installation

### Ubuntu/Debian
```bash
# Install Odin compiler
wget https://github.com/odin-lang/Odin/releases/download/dev-2024-11/odin-linux-amd64-dev-2024-11.tar.gz
tar -xzf odin-linux-amd64-dev-2024-11.tar.gz
sudo mv odin /usr/local/bin/

# Install build tools
sudo apt install nasm binutils xorriso qemu-system-x86 ovmf
```

### Arch Linux
```bash
# Odin from AUR
yay -S odin-git

# Build tools
sudo pacman -S nasm binutils xorriso qemu-base edk2-ovmf
```

### macOS
```bash
# Odin
brew install odin-lang/odin/odin

# Build tools
brew install nasm qemu xorriso
```

## First Build

```bash
cd timeless-os

# Verify Odin installation
odin version

# Build the kernel
./build/build.sh

# Check output
ls -lh build/output/
```

## Running in QEMU

### Basic Boot
```bash
./build/build.sh run
```

### With Debugging
```bash
qemu-system-x86_64 \
    -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd \
    -cdrom build/output/timelessos.iso \
    -m 2048 \
    -smp 2 \
    -serial stdio \
    -display gtk
```

### With GDB Debugging
```bash
# Start QEMU with GDB stub
qemu-system-x86_64 \
    -cdrom build/output/timelessos.iso \
    -m 2048 \
    -s -S \
    -serial stdio

# In another terminal
gdb build/output/TimelessOS.efi
(gdb) target remote :1234
(gdb) break efi_main
(gdb) continue
```

## Expected Output

On successful boot, you should see:

```
TimelessOS Kernel Starting...
UEFI Handle: 0x...
System Table: 0x...
CPU: Intel(R) Core(TM) i7-...
CPU: Family 6, Model 158, Stepping 10
Features: FPU APIC SSE SSE2 SSE3 SSSE3 SSE4.1 SSE4.2 AVX SMEP SMAP
Physical Memory: Initializing...
Physical Memory: Largest RAM region: 0x200000 - 0x80000000 (2040 MB)
Physical Memory: Initialized (522240 frames, 2040 MB)
Virtual Memory: Initializing...
Virtual Memory: Paging enabled
Kernel Heap: Initialized at 0xFFFF800010000000
IDT: Initializing...
IDT: 256 entries configured
PIC: Initializing and remapping IRQs...
PIC: Remapped IRQ0-IRQ15 to vectors 32-47
APIC: Initializing...
APIC: Local APIC ID: 0
APIC: Base address: 0xFEE00000
APIC: Enabled
Interrupts: Enabled
VGA: Text mode initialized (80x25)
Keyboard: PS/2 keyboard initialized
Mouse: PS/2 mouse initialized
GPU: Detecting hardware...
GPU: Intel Integrated Graphics detected (0x5912)
Intel GPU: Initializing...
Intel GPU: Initialized
Dinit: Initializing service manager...
Dinit: Service manager initialized
Dinit: Starting boot process...
Dinit: Setting target to 'multi-user'
Dinit: Starting service 'syslog': System Logger
Dinit: Service 'syslog' started (PID: 101)
...
Kernel initialization complete
Starting user-space environment...
```

## Troubleshooting

### Odin Not Found
```bash
# Check PATH
echo $PATH

# Add Odin to PATH
export PATH=$PATH:/path/to/odin
```

### UEFI Boot Fails
- Ensure OVMF firmware is installed
- Try with `-bios OVMF.fd` instead of pflash drives
- Check ISO was created correctly: `file build/output/timelessos.iso`

### Triple Fault (QEMU resets)
- Check serial output for panic messages
- Enable debug logging in build_config.odin
- Use GDB to find crash location

### No Video Output
- Check VGA driver initialized in logs
- Try with `-display sdl` or `-display gtk`
- Verify VGA buffer mapping in virtual.odin

## Next Steps

1. **Explore the codebase**
   ```bash
   # Find all Odin files
   find kernel -name "*.odin" | head -20
   
   # Search for specific functionality
   grep -r "interrupt" kernel/
   ```

2. **Modify and rebuild**
   ```bash
   # Edit a driver
   vim kernel/drivers/serial/uart.odin
   
   # Rebuild
   ./build/build.sh
   ```

3. **Add a service**
   ```odin
   // In kernel/services/dinit.odin
   register_service(Service{
       name = "my-service",
       command = "/sbin/my-service",
       restart_policy = .Always,
   })
   ```

4. **Implement a feature**
   - Check the TODO list in README.md
   - Start with something small (e.g., add a syscall)
   - Test thoroughly in QEMU

## Development Tips

### Odin Language Resources
- Official docs: https://odin-lang.org/docs/
- Odin Discord: https://discord.gg/odin-lang
- Examples: https://github.com/odin-lang/Odin/tree/master/examples

### OSDev Resources
- OSDev Wiki: https://wiki.osdev.org/
- OSDev Forum: https://forum.osdev.org/
- r/OSDev: https://reddit.com/r/osdev

### Debugging Tips
1. Use serial console for early boot issues
2. Add `log.info()` statements liberally
3. Use QEMU's `-d int` to trace interrupts
4. Check memory maps with `(gdb) x/10gx 0x...`

## Getting Help

- Open an issue on the project repository
- Join the Odin Discord #osdev channel
- Check existing issues for similar problems

Happy hacking! 🚀
