// TimelessOS Dinit - UEFI Service Manager
// Ported from C to Odin for native kernel integration

package services.dinit

import (
    "core:mem"
    "core:log"
    "core:fmt"
    "core:strings"
    "mm:heap"
    "arch:x86_64/cpu"
)

// ============================================================================
// Handoff Structure (matches bootloader handoff)
// ============================================================================

DINIT_HANDOFF_MAGIC :: 0x44494E49543031  // "DINIT01"
DINIT_HANDOFF_VERSION :: 0x00010000       // v0.1.0

// Handoff from bootloader/early kernel init
Dinit_Handoff :: struct {
    magic:              u64,
    version:            u32,
    flags:              u32,
    
    // Memory map
    memory_map_addr:    uintptr,
    memory_map_size:    usize,
    memory_desc_size:   usize,
    memory_desc_version: u32,
    
    // Graphics info
    graphics: struct {
        framebuffer_addr: uintptr,
        framebuffer_size: usize,
        width:            u32,
        height:           u32,
        pitch:            u32,
        bpp:              u32,
        format:           u32,
    },
    
    // ACPI tables
    acpi: struct {
        rsdp_addr: uintptr,
        xsdt_addr: uintptr,
        rsdt_addr: uintptr,
    },
    
    // Kernel info
    kernel: struct {
        kernel_addr: uintptr,
        kernel_size: usize,
        entry_point: uintptr,
    },
    
    // Service config
    service_config: struct {
        service_dir:     [256]u16,  // UTF-16 path
        config_file:     [256]u16,
        log_dir:         [256]u16,
        default_runlevel: [32]u16,
    },
    
    boot_flags: u32,
    boot_args:  [512]u16,
    boot_time:  u64,
}


// ============================================================================
// Service Definitions
// ============================================================================

MAX_SERVICES :: 64
MAX_DEPS :: 16
MAX_NAME_LEN :: 64
MAX_PATH_LEN :: 256

Service_State :: enum {
    Stopped,
    Starting,
    Running,
    Stopping,
    Failed,
    Disabled,
}

Service :: struct {
    name:             [MAX_NAME_LEN]u8,
    command:          [MAX_PATH_LEN]u8,
    dependencies:     [MAX_DEPS][MAX_NAME_LEN]u8,
    dep_count:        int,
    state:            Service_State,
    enabled:          bool,
    restart_on_failure: bool,
    restart_delay:    i64,  // microseconds
    pid:              int,
    exit_code:        int,
    restart_count:    int,
    max_restarts:     int,
}


// ============================================================================
// Service Manager State
// ============================================================================

Service_Manager :: struct {
    handoff:          *Dinit_Handoff,
    services:         []Service,
    service_count:    int,
    running_count:    int,
    failed_count:     int,
    boot_stage:       int,
    current_target:   string,
    event_loop_active: bool,
}

manager: Service_Manager


// ============================================================================
// Initialize Dinit
// ============================================================================

init :: proc() {
    log.info("Dinit: Initializing service manager (UEFI-native)...")
    
    manager = Service_Manager{
        handoff = nil,
        services = make([]Service, MAX_SERVICES),
        service_count = 0,
        running_count = 0,
        failed_count = 0,
        boot_stage = 0,
        current_target = "multi-user",
        event_loop_active = false,
    }
    
    log.info("Dinit: Service table allocated (%d slots)", MAX_SERVICES)
}


// Initialize with Handoff (called from bootloader)
init_with_handoff :: proc(handoff: *Dinit_Handoff) -> bool {
    log.info("Dinit: Initializing with bootloader handoff...")
    
    // Validate handoff
    if handoff == nil {
        log.error("Dinit: NULL handoff")
        return false
    }
    
    if handoff.magic != DINIT_HANDOFF_MAGIC {
        log.error("Dinit: Invalid handoff magic (0x%X)", handoff.magic)
        return false
    }
    
    log.info("Dinit: Handoff validated (version %d.%d)",
             handoff.version >> 16, handoff.version & 0xFFFF)
    
    manager.handoff = handoff
    
    // Print boot info
    log.info("Dinit: Boot time: %d ms", handoff.boot_time)
    log.info("Dinit: Graphics: %dx%d@%d",
             handoff.graphics.width,
             handoff.graphics.height,
             handoff.graphics.bpp)
    
    // Print ACPI info
    if handoff.acpi.rsdp_addr != 0 {
        log.info("Dinit: ACPI RSDP at 0x%p", handoff.acpi.rsdp_addr)
    }
    
    // Print memory map info
    log.info("Dinit: Memory map: %d bytes, %d desc size",
             handoff.memory_map_size,
             handoff.memory_desc_size)
    
    return true
}


// ============================================================================
// Service Discovery
// ============================================================================

discover_services :: proc() -> int {
    log.info("Dinit: Discovering services...")
    
    manager.service_count = 0
    
    // For now, hardcode default services
    // In full implementation, parse service files from disk
    
    // USB Service
    register_service(Service{
        name = "usb",
        command = "/EFI/drivers/usb.efi",
        dep_count = 0,
        enabled = true,
        restart_on_failure = true,
        restart_delay = 2000000,  // 2 seconds
        max_restarts = 3,
    })
    
    // Network Service
    register_service(Service{
        name = "network",
        command = "/EFI/drivers/network.efi",
        dep_count = 0,
        enabled = true,
        restart_on_failure = true,
        restart_delay = 2000000,
        max_restarts = 3,
    })
    
    // Filesystem Service
    register_service(Service{
        name = "filesystem",
        command = "/EFI/drivers/filesystem.efi",
        dependencies = {"usb"},
        dep_count = 1,
        enabled = true,
        restart_on_failure = true,
        restart_delay = 2000000,
        max_restarts = 3,
    })
    
    // Session Service (user desktop)
    register_service(Service{
        name = "session",
        command = "/EFI/session/session.efi",
        dependencies = {"network", "usb", "filesystem"},
        dep_count = 3,
        enabled = true,
        restart_on_failure = false,
        restart_delay = 0,
        max_restarts = 1,
    })
    
    // Syslog Service
    register_service(Service{
        name = "syslog",
        command = "/EFI/services/syslog.efi",
        dep_count = 0,
        enabled = true,
        restart_on_failure = true,
        restart_delay = 1000000,
        max_restarts = 5,
    })
    
    log.info("Dinit: Discovered %d services", manager.service_count)
    
    return manager.service_count
}


// Register a Service
register_service :: proc(service: Service) -> bool {
    if manager.service_count >= MAX_SERVICES {
        log.error("Dinit: Service table full")
        return false
    }
    
    manager.services[manager.service_count] = service
    manager.service_count++
    
    log.debug("Dinit: Registered service '%s'", service.name)
    
    return true
}


// ============================================================================
// Dependency Resolution
// ============================================================================

// Find service by name
find_service :: proc(name: string) -> *Service {
    for i in 0..<manager.service_count {
        svc := &manager.services[i]
        svc_name := string(svc.name[:])
        
        // Trim null terminator
        if idx := strings.index_char(svc_name, 0); idx >= 0 {
            svc_name = svc_name[:idx]
        }
        
        if svc_name == name {
            return svc
        }
    }
    return nil
}


// Check if all dependencies are satisfied
deps_satisfied :: proc(svc: *Service) -> bool {
    for i in 0..<svc.dep_count {
        dep_name := string(svc.dependencies[i][:])
        if idx := strings.index_char(dep_name, 0); idx >= 0 {
            dep_name = dep_name[:idx]
        }
        
        dep := find_service(dep_name)
        if dep == nil || dep.state != .Running {
            return false
        }
    }
    return true
}


// Topological sort for service startup order
resolve_dependencies :: proc() {
    log.info("Dinit: Resolving dependencies...")
    
    // Simple bubble sort based on dependency count
    // (Real implementation would use proper topological sort)
    
    for i in 0..<manager.service_count - 1 {
        for j in 0..<manager.service_count - i - 1 {
            svc1 := &manager.services[j]
            svc2 := &manager.services[j + 1]
            
            if svc1.dep_count > svc2.dep_count {
                // Swap
                tmp := svc1[]
                svc1[] = svc2[]
                svc2[] = tmp
            }
        }
    }
    
    log.info("Dinit: Dependencies resolved")
}


// ============================================================================
// Service Execution
// ============================================================================

start_service :: proc(svc: *Service) -> bool {
    if svc == nil {
        return false
    }
    
    if !svc.enabled {
        log.debug("Dinit: Service '%s' is disabled", svc.name)
        return false
    }
    
    if svc.state == .Running {
        log.debug("Dinit: Service '%s' already running", svc.name)
        return true
    }
    
    if !deps_satisfied(svc) {
        log.warn("Dinit: Dependencies not met for '%s'", svc.name)
        return false
    }
    
    log.info("Dinit: Starting service '%s'...", svc.name)
    svc.state = .Starting
    
    // In UEFI environment, load and start EFI image
    // In kernel environment, fork/exec process
    success := load_and_start_service(svc)
    
    if success {
        svc.state = .Running
        manager.running_count++
        log.info("Dinit: Service '%s' started (PID: %d)", svc.name, svc.pid)
    } else {
        svc.state = .Failed
        manager.failed_count++
        log.error("Dinit: Service '%s' failed to start", svc.name)
        
        if svc.restart_on_failure {
            schedule_restart(svc)
        }
    }
    
    return success
}


// Load and Start Service (UEFI version)
load_and_start_service :: proc(svc: *Service) -> bool {
    // In real UEFI implementation:
    // 1. Use LoadImage to load EFI binary
    // 2. Use StartImage to execute
    // 3. Store image handle
    
    // For now, simulate success
    svc.pid = 100 + manager.service_count
    
    log.debug("Dinit: Loaded %s (simulated)", svc.command)
    
    return true
}


// Stop a Service
stop_service :: proc(svc: *Service) -> bool {
    if svc == nil {
        return false
    }
    
    if svc.state != .Running {
        return true
    }
    
    log.info("Dinit: Stopping service '%s'...", svc.name)
    svc.state = .Stopping
    
    // In real implementation:
    // 1. Send stop signal/command
    // 2. Wait for graceful shutdown
    // 3. Unload image/kill process
    
    svc.state = .Stopped
    manager.running_count--
    
    log.info("Dinit: Service '%s' stopped", svc.name)
    
    return true
}


// Restart a Service
restart_service :: proc(svc: *Service) -> bool {
    if svc == nil {
        return false
    }
    
    log.info("Dinit: Restarting service '%s'...", svc.name)
    
    if !stop_service(svc) {
        return false
    }
    
    svc.restart_count++
    
    if svc.restart_count > svc.max_restarts {
        log.error("Dinit: Service '%s' exceeded max restarts (%d/%d)",
                  svc.name, svc.restart_count, svc.max_restarts)
        svc.state = .Failed
        manager.failed_count++
        return false
    }
    
    // Delay before restart
    if svc.restart_delay > 0 {
        log.info("Dinit: Waiting %d µs before restart", svc.restart_delay)
        // In real implementation: stall or schedule timer
    }
    
    return start_service(svc)
}


// Schedule Service Restart
schedule_restart :: proc(svc: *Service) {
    svc.restart_count++
    
    if svc.restart_count > svc.max_restarts {
        log.error("Dinit: Service '%s' exceeded max restarts", svc.name)
        svc.state = .Failed
        manager.failed_count++
        return
    }
    
    log.info("Dinit: Scheduling restart for '%s' (attempt %d/%d)",
             svc.name, svc.restart_count, svc.max_restarts)
    
    // In real implementation, set timer and return to event loop
    start_service(svc)
}


// ============================================================================
// Boot Targets (Runlevels)
// ============================================================================

set_target :: proc(target: string) {
    log.info("Dinit: Setting target to '%s'", target)
    manager.current_target = target
    
    start_target(target)
}


start_target :: proc(target: string) {
    switch target {
    case "emergency":
        // Minimal services
        start_service(find_service("syslog"))
        
    case "rescue":
        // Single user mode
        start_service(find_service("syslog"))
        
    case "multi-user":
        // Full multi-user, no GUI
        start_service(find_service("syslog"))
        start_service(find_service("usb"))
        start_service(find_service("network"))
        start_service(find_service("filesystem"))
        
    case "graphical":
        // Full GUI with session
        start_service(find_service("syslog"))
        start_service(find_service("usb"))
        start_service(find_service("network"))
        start_service(find_service("filesystem"))
        start_service(find_service("session"))
        
    case "shutdown":
        shutdown()
    }
}


// ============================================================================
// Event Loop
// ============================================================================

event_loop :: proc() {
    log.info("Dinit: Entering service supervision loop")
    log.info("Dinit: Monitoring %d services", manager.service_count)
    
    manager.event_loop_active = true
    
    for manager.event_loop_active {
        // Monitor services
        monitor_services()
        
        // Check for failed services
        check_failed_services()
        
        // In real implementation:
        // - Wait for events (service exits, timers, signals)
        // - Use UEFI WaitForEvent or kernel wait queues
        
        // For now, halt CPU until interrupt
        cpu.halt()
    }
}


// Monitor All Services
monitor_services :: proc() {
    for i in 0..<manager.service_count {
        svc := &manager.services[i]
        
        if svc.state == .Running {
            // Check if service is still alive
            // In real implementation, check PID or image handle
            if !is_service_alive(svc) {
                log.warn("Dinit: Service '%s' died unexpectedly", svc.name)
                svc.state = .Failed
                
                if svc.restart_on_failure {
                    schedule_restart(svc)
                }
            }
        }
    }
}


// Check if Service is Alive
is_service_alive :: proc(svc: *Service) -> bool {
    // In real implementation:
    // - Check process table
    // - Check EFI image handle status
    // - Use waitpid or similar
    
    return true  // Simulated
}


// Check Failed Services
check_failed_services :: proc() {
    if manager.failed_count > 0 {
        log.warn("Dinit: %d service(s) in failed state", manager.failed_count)
        
        // Log failed services
        for i in 0..<manager.service_count {
            svc := &manager.services[i]
            if svc.state == .Failed {
                log.warn("  - %s (restarts: %d/%d)",
                         svc.name, svc.restart_count, svc.max_restarts)
            }
        }
    }
}


// ============================================================================
// Service Status
// ============================================================================

list_services :: proc() {
    log.info("=== Dinit Service List ===")
    log.info("%-20s %-30s %-12s %-8s %-8s",
             "Name", "Command", "State", "PID", "Restarts")
    log.info("%s", strings.repeat("=", 85))
    
    for i in 0..<manager.service_count {
        svc := &manager.services[i]
        name := string(svc.name[:])
        command := string(svc.command[:])
        
        pid_str := "-"
        if svc.pid > 0 {
            pid_str = fmt.sprintf("%d", svc.pid)
        }
        
        restart_str := fmt.sprintf("%d/%d", svc.restart_count, svc.max_restarts)
        
        log.info("%-20s %-30s %-12s %-8s %-8s",
                 name, command, svc.state, pid_str, restart_str)
    }
}


get_service_status :: proc(name: string) -> Service_State {
    svc := find_service(name)
    if svc == nil {
        return .Stopped
    }
    return svc.state
}


// ============================================================================
// Shutdown
// ============================================================================

shutdown :: proc() {
    log.info("Dinit: Initiating shutdown...")
    
    // Stop all services in reverse order
    for i in manager.service_count - 1; i >= 0; i-- {
        svc := &manager.services[i]
        if svc.state == .Running {
            stop_service(svc)
        }
    }
    
    log.info("Dinit: All services stopped")
    log.info("Dinit: System ready for power off")
    
    // In real implementation, call ACPI power off
    // acpi.power_off()
    
    manager.event_loop_active = false
}


reboot :: proc() {
    log.info("Dinit: Initiating reboot...")
    shutdown()
    
    // In real implementation, trigger CPU reset
    // cpu.reset()
}


// ============================================================================
// Handoff Validation
// ============================================================================

validate_handoff :: proc(handoff: *Dinit_Handoff) -> bool {
    if handoff == nil {
        return false
    }
    
    if handoff.magic != DINIT_HANDOFF_MAGIC {
        log.error("Dinit: Invalid handoff magic")
        return false
    }
    
    // Validate memory map
    if handoff.memory_map_addr == 0 || handoff.memory_map_size == 0 {
        log.error("Dinit: Invalid memory map in handoff")
        return false
    }
    
    // Validate graphics (optional)
    if (handoff.flags & 0x01) != 0 {
        if handoff.graphics.framebuffer_addr == 0 {
            log.error("Dinit: Graphics enabled but no framebuffer")
            return false
        }
    }
    
    return true
}


// ============================================================================
// Getters
// ============================================================================

get_service_count :: proc() -> int {
    return manager.service_count
}

get_running_count :: proc() -> int {
    return manager.running_count
}

get_failed_count :: proc() -> int {
    return manager.failed_count
}

get_boot_stage :: proc() -> int {
    return manager.boot_stage
}

get_current_target :: proc() -> string {
    return manager.current_target
}

is_active :: proc() -> bool {
    return manager.event_loop_active
}
