// Dinit Service Manager
// Init system and service manager for TimelessOS

package services.dinit

import (
    "core:log"
    "core:fmt"
    "core:strings"
    "mm:heap"
    "arch:x86_64/cpu"
)

// Service States
Service_State :: enum {
    Stopped,
    Starting,
    Running,
    Stopping,
    Failed,
    Waiting,
}

// Service Types
Service_Type :: enum {
    Process,      // Regular process
    Internal,     // Internal service (handled by dinit)
    Script,       // Shell script
}

// Service Definition
Service :: struct {
    name:           string,
    description:    string,
    state:          Service_State,
    service_type:   Service_Type,
    command:        string,
    args:           []string,
    working_dir:    string,
    user:           string,
    group:          string,
    dependencies:   []string,
    dependents:     []string,
    restart_policy: Restart_Policy,
    max_restarts:   int,
    restart_count:  int,
    timeout:        u32,  // Seconds
    pid:            int,
    exit_code:      int,
    log_file:       string,
    env:            []string,
}

// Restart Policy
Restart_Policy :: enum {
    Never,
    On_Failure,
    Always,
}

// Service Manager State
Service_Manager :: struct {
    services:       []Service,
    service_count:  int,
    boot_stage:     int,
    current_target: string,
    log_level:      log.Level,
}

// Boot Targets (Runlevels)
BOOT_TARGETS :: [5]string = {
    "emergency",
    "rescue",
    "multi-user",
    "graphical",
    "shutdown",
}

// Global service manager
manager: Service_Manager


// Initialize Service Manager
init :: proc() {
    log.info("Dinit: Initializing service manager...")
    
    manager = Service_Manager{
        services = make([]Service, 64),
        service_count = 0,
        boot_stage = 0,
        current_target = "multi-user",
        log_level = .INFO,
    }
    
    // Register core services
    register_core_services()
    
    log.info("Dinit: Service manager initialized")
}


// Register Core Services
register_core_services :: proc() {
    // System logger
    register_service(Service{
        name = "syslog",
        description = "System Logger",
        service_type = .Process,
        command = "/sbin/syslogd",
        args = {"-n"},
        restart_policy = .Always,
        max_restarts = 3,
        timeout = 30,
    })
    
    // Device manager
    register_service(Service{
        name = "devmgr",
        description = "Device Manager",
        service_type = .Process,
        command = "/sbin/devmgrd",
        restart_policy = .Always,
        max_restarts = 3,
        timeout = 30,
    })
    
    // Network manager
    register_service(Service{
        name = "network",
        description = "Network Manager",
        service_type = .Process,
        command = "/sbin/netmgrd",
        dependencies = {"devmgr"},
        restart_policy = .On_Failure,
        max_restarts = 3,
        timeout = 60,
    })
    
    // Display manager (graphical target)
    register_service(Service{
        name = "display-manager",
        description = "Display Manager",
        service_type = .Process,
        command = "/sbin/greetd",
        dependencies = {"network", "syslog"},
        restart_policy = .On_Failure,
        max_restarts = 2,
        timeout = 30,
    })
    
    // SSH daemon
    register_service(Service{
        name = "sshd",
        description = "OpenSSH Daemon",
        service_type = .Process,
        command = "/sbin/sshd",
        args = {"-D"},
        dependencies = {"network"},
        restart_policy = .Always,
        max_restarts = 5,
        timeout = 30,
    })
    
    // Cron daemon
    register_service(Service{
        name = "cron",
        description = "Cron Daemon",
        service_type = .Process,
        command = "/sbin/crond",
        dependencies = {"syslog"},
        restart_policy = .Always,
        max_restarts = 3,
        timeout = 30,
    })
}


// Register a Service
register_service :: proc(service: Service) {
    if manager.service_count >= len(manager.services) {
        log.error("Dinit: Service table full")
        return
    }
    
    manager.services[manager.service_count] = service
    manager.service_count++
    
    log.debug("Dinit: Registered service '%s'", service.name)
}


// Start Service Manager (Begin Boot)
start :: proc() {
    log.info("Dinit: Starting boot process...")
    
    // Start with emergency target
    set_target("emergency")
    
    // Progress through boot stages
    manager.boot_stage = 1
    
    // Start essential services
    start_service("syslog")
    start_service("devmgr")
    
    manager.boot_stage = 2
    
    // Start network
    start_service("network")
    
    manager.boot_stage = 3
    
    // Start remaining services based on target
    start_target(manager.current_target)
    
    log.info("Dinit: Boot complete")
}


// Set Boot Target
set_target :: proc(target: string) {
    manager.current_target = target
    log.info("Dinit: Setting target to '%s'", target)
}


// Start Target (Runlevel)
start_target :: proc(target: string) {
    switch target {
    case "emergency":
        // Minimal services only
        start_service("syslog")
        
    case "rescue":
        // Single user mode
        start_service("syslog")
        start_service("devmgr")
        
    case "multi-user":
        // Full multi-user, no GUI
        start_service("syslog")
        start_service("devmgr")
        start_service("network")
        start_service("sshd")
        start_service("cron")
        
    case "graphical":
        // Full GUI
        start_service("syslog")
        start_service("devmgr")
        start_service("network")
        start_service("sshd")
        start_service("cron")
        start_service("display-manager")
        
    case "shutdown":
        shutdown()
    }
}


// Start a Service
start_service :: proc(name: string) -> bool {
    service := find_service(name)
    if service == nil {
        log.error("Dinit: Service '%s' not found", name)
        return false
    }
    
    if service.state == .Running {
        log.debug("Dinit: Service '%s' already running", name)
        return true
    }
    
    if service.state == .Starting {
        log.debug("Dinit: Service '%s' already starting", name)
        return true
    }
    
    // Check dependencies
    for _, dep in service.dependencies {
        dep_service := find_service(dep)
        if dep_service == nil || dep_service.state != .Running {
            log.info("Dinit: Starting dependency '%s' for '%s'", dep, name)
            if !start_service(dep) {
                log.error("Dinit: Failed to start dependency '%s'", dep)
                return false
            }
        }
    }
    
    // Start the service
    log.info("Dinit: Starting service '%s': %s", name, service.description)
    service.state = .Starting
    
    success := start_service_process(service)
    
    if success {
        service.state = .Running
        log.info("Dinit: Service '%s' started (PID: %d)", name, service.pid)
    } else {
        service.state = .Failed
        log.error("Dinit: Service '%s' failed to start", name)
        
        if service.restart_policy == .On_Failure {
            retry_start_service(service)
        }
    }
    
    return success
}


// Start Service Process
start_service_process :: proc(service: *Service) -> bool {
    // In real implementation, this would:
    // 1. Fork a new process
    // 2. Set up environment
    // 3. Execute the command
    // 4. Return the PID
    
    // For now, simulate success
    service.pid = 100 + manager.service_count
    return true
}


// Stop a Service
stop_service :: proc(name: string) -> bool {
    service := find_service(name)
    if service == nil {
        return false
    }
    
    if service.state != .Running {
        return true
    }
    
    log.info("Dinit: Stopping service '%s'", name)
    service.state = .Stopping
    
    // Send SIGTERM
    send_signal(service.pid, 15)  // SIGTERM
    
    // Wait for timeout
    timeout := service.timeout
    for timeout > 0 {
        if !is_process_running(service.pid) {
            service.state = .Stopped
            log.info("Dinit: Service '%s' stopped", name)
            return true
        }
        timeout--
        cpu.pause()
    }
    
    // Force kill
    log.warn("Dinit: Service '%s' didn't stop, sending SIGKILL", name)
    send_signal(service.pid, 9)  // SIGKILL
    service.state = .Stopped
    
    return true
}


// Restart a Service
restart_service :: proc(name: string) -> bool {
    service := find_service(name)
    if service == nil {
        return false
    }
    
    log.info("Dinit: Restarting service '%s'", name)
    
    if !stop_service(name) {
        return false
    }
    
    service.restart_count++
    if service.restart_count > service.max_restarts {
        log.error("Dinit: Service '%s' exceeded max restarts", name)
        service.state = .Failed
        return false
    }
    
    return start_service(name)
}


// Retry Start After Failure
retry_start_service :: proc(service: *Service) {
    service.restart_count++
    
    if service.restart_count > service.max_restarts {
        log.error("Dinit: Service '%s' exceeded max restarts (%d)",
                  service.name, service.max_restarts)
        service.state = .Failed
        return
    }
    
    // Exponential backoff
    delay := 1 << service.restart_count  // 2, 4, 8, 16... seconds
    log.info("Dinit: Retrying '%s' in %d seconds (attempt %d/%d)",
             service.name, delay, service.restart_count, service.max_restarts)
    
    // In real implementation, schedule retry
    start_service(service.name)
}


// Get Service Status
get_service_status :: proc(name: string) -> Service_State {
    service := find_service(name)
    if service == nil {
        return .Stopped
    }
    return service.state
}


// List Services
list_services :: proc() {
    log.info("=== Dinit Service List ===")
    log.info("%-20s %-30s %-12s %-8s", "Name", "Description", "State", "PID")
    log.info("%s", strings.repeat("=", 75))
    
    for i in 0..<manager.service_count {
        service := manager.services[i]
        pid_str := "-"
        if service.pid > 0 {
            pid_str = fmt.sprintf("%d", service.pid)
        }
        log.info("%-20s %-30s %-12s %-8s",
                 service.name, service.description, service.state, pid_str)
    }
}


// Find Service by Name
find_service :: proc(name: string) -> *Service {
    for i in 0..<manager.service_count {
        if manager.services[i].name == name {
            return &manager.services[i]
        }
    }
    return nil
}


// Send Signal to Process
send_signal :: proc(pid: int, signal: int) {
    // In real implementation, send signal via syscall
}


// Check if Process is Running
is_process_running :: proc(pid: int) -> bool {
    // In real implementation, check process table
    return false
}


// Shutdown System
shutdown :: proc() {
    log.info("Dinit: Initiating shutdown...")
    
    // Stop all services in reverse order
    for i in manager.service_count - 1; i >= 0; i-- {
        service := &manager.services[i]
        if service.state == .Running {
            stop_service(service.name)
        }
    }
    
    log.info("Dinit: All services stopped")
    log.info("Dinit: System ready for power off")
    
    // In real implementation, call ACPI power off
}


// Reboot System
reboot :: proc() {
    log.info("Dinit: Initiating reboot...")
    shutdown()
    
    // In real implementation, trigger CPU reset
}


// Get Boot Stage
get_boot_stage :: proc() -> int {
    return manager.boot_stage
}


// Get Current Target
get_current_target :: proc() -> string {
    return manager.current_target
}
