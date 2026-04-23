// Advanced CPU Management
// Phase 1.3: Microcode updates, frequency scaling, C-states, performance counters
// Supports: Intel, AMD, VM (VMware, QEMU/KVM)

package arch.x86_64.cpu

import (
    "core:intrinsics"
    "core:log"
    "core:mem"
    "core:sync"
)

PAGE_SIZE :: 4096
MICROCODE_SIZE_MAX :: 2048

MSR_IA32_PERF_STATUS :: 0x198
MSR_IA32_PERF_CTL :: 0x199
MSR_IA32_CLOCK_MODULATION :: 0x19A
MSR_IA32_THERMAL_STATUS :: 0x19B
MSR_IA32_THERMAL_MIN :: 0x19C
MSR_IA32_MISC_ENABLE :: 0x1A0
MSR_IA32_MC0_CTL :: 0x400
MSR_IA32_MC0_STATUS :: 0x401
MSR_IA32_TSC_DEADLINE :: 0x6E0
MSR_IA32_UCODE_WRITE :: 0x79
MSR_IA32_UCODE_REV :: 0x8B

MSR_AMD_PERF_STATUS :: 0xC0010063
MSR_AMD_PERF_CTL :: 0xC0010062
MSR_AMD_TEMPERATURE :: 0xC0010061
MSR_AMD_PSTATE_0 :: 0xC0010064
MSR_AMD_PSTATE_1 :: 0xC0010065
MSR_AMD_PSTATE_2 :: 0xC0010066
MSR_AMD_PSTATE_3 :: 0xC0010067
MSR_AMD_PSTATE_4 :: 0xC0010068
MSR_AMD_PSTATE_5 :: 0xC0010069
MSR_AMD_PSTATE_6 :: 0xC001006A
MSR_AMD_PSTATE_7 :: 0xC001006B
MSR_AMD_P_STATE_CONTROL :: 0xC0010062
MSR_AMD_P_STATE_STATUS :: 0xC0010063
MSR_AMD_UCODE_UPDATE_ADDR :: 0xC0010020
MSR_AMD_UCODE_UPDATE_DATA :: 0xC0010021
MSR_AMD_UCODE_UPDATE_STATUS :: 0xC0010022

PMU_MSR_EVENT_SELECT :: 0xC1
PMU_MSR_COUNTER :: 0xC2
PMU_GLOBAL_CONTROL :: 0x38F
PMU_GLOBAL_STATUS :: 0x38E
PMU_GLOBAL_OVF :: 0x390

CPU_Vendor :: enum {
    Unknown,
    Intel,
    AMD,
    VIA,
    VM_VMware,
    VM_QEMU,
    VM_HyperV,
}

CPU_Type :: enum {
    Desktop,
    Server,
    Mobile,
    Embedded,
    VM_Paravirtual,
}

Cpuid_Function :: enum {
    Cache_Info = 0x02
    TSC = 0x03
    Monitor_MWAIT = 0x05
    Thermal_Power = 0x06
    Extended_Features = 0x07
    Performance_Monitoring = 0x0A
    Topology_Info = 0x0B
    XSAVE = 0x0D
}

CPU_Capabilities :: struct {
    has_tsc: bool,
    has_invar_tsc: bool,
    has_mwait: bool,
    has_aperfmperf: bool,
    has_pat: bool,
    has_pse36: bool,
    has_mce: bool,
    has_mca: bool,
    has_cx16: bool,
    has_x2apic: bool,
    has_xsave: bool,
    has_avx: bool,
    has_avx512: bool,
    has_avx512f: bool,
    has_rtm: bool,
    has_pt: bool,
    has_rapic: bool,
    clflush_size: u8,
    cacheline_size: u8,
    max_cstate: u32,
    monitor_line_size: u16,
}

CPU_Info :: struct {
    vendor: CPU_Vendor,
    type: CPU_Type,
    family: u8,
    model: u8,
    stepping: u8,
    cores_per_package: u8,
    threads_per_core: u8,
    logical_per_package: u8,
    package_id: u8,
    cores_per_die: u8,
    dies_per_package: u8,
    capabilities: CPU_Capabilities,
}

Microcode_Header :: struct {
    header_version: u32,
    update_revision: u32,
    date: u32,
    year: u16,
    day: u8,
    month: u8,
    flags: u32,
    total_size: u32,
    header_size: u32,
    update_data_size: u32,
    processor_flags: [8]u8,
}

Microcode_Update :: struct {
    data: ^u8,
    size: u32,
    revision: u32,
    loaded: bool,
}

Performance_Info :: struct {
    version: u8,
    number_of_counters: u8,
    counter_width: u8,
    ebx_bitmask: u32,
    counters: []Performance_Counter,
}

Performance_Counter :: struct {
    index: u8,
    type: u8,
    unit: u8,
    eventselect: u32,
    enabled: bool,
    running: u64,
    fixed: bool,
    flags: u32,
}

PMU_Counter :: struct {
    config: u64,
    enabled: bool,
    event: u32,
    umask: u8,
    edge: bool,
    precise: u8,
    inv: bool,
    cmask: u8,
}

Global_Control :: struct {
    enable: bool,
    reset: bool,
    enable_os: bool,
    enable_user: bool,
    enable_pmi: bool,
    enable_fixed: bool,
    freeze_on_pmi: bool,
    enable_freeze: bool,
}

info: CPU_Info
microcode: Microcode_Update
perf_info: Performance_Info
initialized: bool = false

@(init_priority=101)
init :: proc() {
    log.info("CPU Advanced: Initializing...")
    
    identify_cpu()
    detect_capabilities()
    init_pmu()
    
    initialized = true
    
    log.info("CPU Advanced: %s, family %d, model %d", 
            get_vendor_name(), info.family, info.model)
}

identify_cpu :: proc() {
    vendor_str := get_vendor_string()
    
    info.vendor = .Unknown
    
    #partial
    switch vendor_str {
    case "GenuineIntel":
        info.vendor = .Intel
    case "AuthenticAMD":
        info.vendor = .AMD
    case "VMware":
        info.vendor = .VM_VMware
    case "KVMKVMKVM":
        info.vendor = .VM_QEMU
    case "Microsoft Hv":
        info.vendor = .VM_HyperV
    }
    
    switch info.vendor {
    case .VM_VMware, .VM_QEMU, .VM_HyperV:
        info.type = .VM_Paravirtual
    case:
        info.type = .Desktop
    }
    
    detect_topology()
}

get_vendor_name :: proc() -> string {
    #partial
    switch info.vendor {
    case .Intel: return "Intel"
    case .AMD: return "AMD"
    case .VM_VMware: return "VMware"
    case .VM_QEMU: return "QEMU/KVM"
    case .VM_HyperV: return "Hyper-V"
    }
    return "Unknown"
}

detect_topology :: proc() {
    eax, ebx, _, _ := cpuid(1, 0)
    
    logical := (ebx >> 16) & 0xFF
    info.logical_per_package = u8(logical)
    
    if info.vendor == .AMD {
        detect_amd_topology()
    } else {
        detect_intel_topology()
    }
}

detect_intel_topology :: proc() {
    ebx, _, _, _ := cpuid(0x0B, 0)
    
    threads := ebx & 0xFFFF
    if threads != 0 {
        info.threads_per_core = u8(threads)
    } else {
        info.threads_per_core = 1
    }
    
    info.cores_per_package = u8(info.logical_per_package / info.threads_per_core)
    info.cores_per_die = info.cores_per_package
    info.dies_per_package = 1
}

detect_amd_topology :: proc() {
    _, _, _, edx := cpuid(0x80000008, 0)
    
    nc := u8(edx & 0xFF)
    node_per_pkg := u8((edx >> 8) & 0x0F)
    
    if nc != 0 {
        info.cores_per_package = nc + 1
    } else {
        info.cores_per_package = 1
    }
    
    if info.cores_per_package >= info.logical_per_package {
        info.threads_per_core = 1
    } else {
        info.threads_per_core = info.logical_per_package / info.cores_per_package
    }
    
    info.cores_per_die = info.cores_per_package / node_per_pkg
    info.dies_per_package = node_per_pkg
}

cpuid :: proc(eax: u32, ecx: u32) -> (u32, u32, u32, u32) {
    return intrinsics.cpuid(eax, ecx)
}

rdmsr :: proc(msr: u32) -> u64 {
    return intrinsics.read_msr(msr)
}

wrmsr :: proc(msr: u32, value: u64) {
    intrinsics.write_msr(msr, value)
}

detect_capabilities :: proc() {
    caps := CPU_Capabilities{}
    
    _, _, ecx, edx := cpuid(1, 0)
    
    caps.has_tsc = (edx & (1 << 4)) != 0
    caps.has_mce = (edx & (1 << 6)) != 0
    caps.has_mca = (edx & (1 << 7)) != 0
    caps.has_cx16 = (edx & (1 << 12)) != 0
    caps.has_mwait = (ecx & (1 << 5)) != 0
    caps.has_xsave = (ecx & (1 << 26)) != 0
    caps.has_aperfmperf = (ecx & (1 << 22)) != 0
    caps.has_pat = (edx & (1 << 16)) != 0
    caps.has_pse36 = (edx & (1 << 17)) != 0
    
    caps.clflush_size = u8(((edx >> 8) & 0xFF) * 8)
    caps.cacheline_size = caps.clflush_size
    
    if info.vendor == .AMD {
        caps.max_cstate = detect_amd_max_cstate()
    } else {
        caps.max_cstate = detect_intel_max_cstate()
    }
    
    ebx, _, _, _ := cpuid(u32(Cpuid_Function.Performance_Monitoring), 0)
    
    perf_version := u8(ebx & 0xFF)
    
    if perf_version >= 2 {
        perf_number := u8((ebx >> 8) & 0xFF)
        perf_width := u8((ebx >> 16) & 0xFF)
        
        perf_info.number_of_counters = perf_number
        perf_info.counter_width = perf_width
    }
    
    info.capabilities = caps
}

detect_intel_max_cstate :: proc() -> u32 {
    _, _, _, edx := cpuid(5, 0)
    
    if (edx & (1 << 0)) != 0 {
        return 0
    }
    if (edx & (1 << 2)) != 0 {
        return 2
    }
    
    _, _, _, edx = cpuid(0x6, 0)
    
    if (edx & (1 << 0)) != 0 {
        return 3
    }
    if (edx & (1 << 6)) != 0 {
        return 6
    }
    if (edx & (1 << 7)) != 0 {
        return 7
    }
    if (edx & (1 << 10)) != 0 {
        return 8
    }
    
    return 10
}

detect_amd_max_cstate :: proc() -> u32 {
    _, _, _, edx := cpuid(0x80000007, 0)
    
    if (edx & (1 << 0)) != 0 { return 1 }
    if (edx & (1 << 1)) != 0 { return 2 }
    if (edx & (1 << 2)) != 0 { return 3 }
    if (edx & (1 << 3)) != 0 { return 4 }
    if (edx & (1 << 4)) != 0 { return 5 }
    
    return 6
}

init_pmu :: proc() {
    log.info("PMU: Initializing Performance Monitoring Unit...")
    
    if info.vendor == .VM_QEMU || info.vendor == .VM_VMware {
        log.info("PMU: Running in VM - limited PMU support")
    }
    
    ebx, _, _, _ := cpuid(u32(Cpuid_Function.Performance_Monitoring), 0)
    
    perf_version := u8(ebx & 0xFF)
    if perf_version == 0 {
        log.warn("PMU: Performance monitoring not available")
        return
    }
    
    perf_info.version = perf_version
    perf_info.number_of_counters = u8((ebx >> 8) & 0xFF)
    perf_info.counter_width = u8((ebx >> 16) & 0xFF)
    perf_info.ebx_bitmask = ebx >> 24
    
    counters_size := int(perf_info.number_of_counters)
    if counters_size > 0 && counters_size < 16 {
        perf_info.counters = make([]Performance_Counter, counters_size)
        
        for i in 0..<counters_size {
            perf_info.counters[i].index = u8(i)
            perf_info.counters[i].enabled = false
        }
    }
    
    log.info("PMU: %d counters, %d-bit width", 
            perf_info.number_of_counters, perf_info.counter_width)
}

pmu_reset :: proc() {
    wrmsr(PMU_GLOBAL_CONTROL, 0)
    
    for i := u8(0); i < perf_info.number_of_counters; i++ {
        wrmsr(u32(PMU_MSR_EVENT_SELECT) + u32(i), 0)
    }
}

pmu_global_enable :: proc() {
    control := Global_Control{
        enable = true,
        enable_os = true,
        enable_user = true,
    }
    pmu_global_control(control)
}

pmu_global_control :: proc(ctrl: Global_Control) {
    value: u64 = 0
    
    if ctrl.enable {
        value |= 1
    }
    if ctrl.enable_os {
        value |= (1 << 2)
    }
    if ctrl.enable_user {
        value |= (1 << 3)
    }
    if ctrl.enable_pmi {
        value |= (1 << 20)
    }
    if ctrl.enable_fixed {
        value |= (1 << 12)
    }
    if ctrl.freeze_on_pmi {
        value |= (1 << 11)
    }
    if ctrl.enable_freeze {
        value |= (1 << 8)
    }
    
    wrmsr(PMU_GLOBAL_CONTROL, value)
}

pmu_global_disable :: proc() {
    wrmsr(PMU_GLOBAL_CONTROL, 0)
}

pmu_global_status :: proc() -> u64 {
    return rdmsr(PMU_GLOBAL_STATUS)
}

pmu_enable_counter :: proc(index: u8, enable: bool) {
    if int(index) >= len(perf_info.counters) {
        return
    }
    
    perf_info.counters[index].enabled = enable
    
    msr := u32(PMU_MSR_EVENT_SELECT) + u32(index)
    
    if enable {
        value := perf_info.counters[index].eventselect & 0xFFFFFFFF
        
        if perf_info.counters[index].fixed {
            value |= (1 << 22)
        }
        
        wrmsr(msr, value)
    } else {
        wrmsr(msr, 0)
    }
}

pmu_write_config :: proc(index: u8, config: u64) {
    if int(index) >= len(perf_info.counters) {
        return
    }
    
    perf_info.counters[index].config = config
    
    msr := u32(PMU_MSR_EVENT_SELECT) + u32(index)
    wrmsr(msr, config)
}

pmu_read_counter :: proc(index: u8) -> u64 {
    msr := u32(PMU_MSR_COUNTER) + u32(index)
    return rdmsr(msr)
}

get_tsc_frequency :: proc() -> u64 {
    if !info.capabilities.has_tsc {
        return 0
    }
    
    if info.vendor == .AMD {
        return get_amd_tsc_frequency()
    }
    
    return estimate_tsc_frequency()
}

get_amd_tsc_frequency :: proc() -> u64 {
    if has_cpuid(0x80000007, 0) {
        _, _, _, edx := cpuid(0x80000007, 0)
        
        if (edx & (1 << 7)) != 0 {
            pstate0 := rdmsr(MSR_AMD_PSTATE_0)
            freq_coreid := pstate0 & 0x3F
            
            if has_cpuid(0x80000001, 0) {
                _, _, _, rev_edx := cpuid(0x80000001, 0)
                
                if (rev_edx & (1 << 6)) != 0 {
                    fid := u64(freq_coreid & 0x3F)
                    did := u64((freq_coreid >> 6) & 7)
                    cpu_id := u64((pstate0 >> 8) & 0xFF)
                    
                    if did != 0 {
                        refclk := u64(200)
                        return (fid * refclk * 1000) / (did << cpu_id)
                    }
                }
            }
        }
    }
    
    return estimate_tsc_frequency()
}

estimate_tsc_frequency :: proc() -> u64 {
    timer_base := intrinsics.read_tsc()
    
    intrinsics.sleep(10)
    
    timer_end := intrinsics.read_tsc()
    
    diff := timer_end - timer_base
    
    return diff * 100
}

has_cpuid :: proc(function: u32, subleaf: u32 = 0) -> bool {
    max_func, _, _, _ := cpuid(0, 0)
    
    if function <= max_func {
        return true
    }
    
    if function >= 0x80000000 {
        _, _, _, edx := cpuid(0x80000000, 0)
        if u32(function) <= u32(edx) {
            return true
        }
    }
    
    return false
}

load_microcode :: proc(buffer: ^u8, size: u32) -> bool {
    if buffer == nil || size == 0 || size > MICROCODE_SIZE_MAX {
        return false
    }
    
    microcode.data = buffer
    microcode.size = size
    
    header := cast(^Microcode_Header)(buffer)
    
    if header.header_version != 1 {
        log.error("Microcode: Invalid header version %d", header.header_version)
        return false
    }
    
    if info.vendor == .Intel {
        return load_intel_microcode()
    } else if info.vendor == .AMD {
        return load_amd_microcode()
    }
    
    log.warn("Microcode: Vendor not supported for updates")
    return false
}

load_intel_microcode :: proc() -> bool {
    if !info.capabilities.has_mca {
        log.warn("Microcode: MCA not supported")
        return false
    }
    
    header := cast(^Microcode_Header)(microcode.data)
    update_revision := header.update_revision
    
    log.info("Microcode: Loading Intel revision 0x%X", update_revision)
    
    current := rdmsr(MSR_IA32_UCODE_REV)
    current_rev := u32(current & 0xFFFFFFFF)
    
    if current_rev == update_revision {
        log.info("Microcode: Already at revision 0x%X", update_revision)
        microcode.revision = update_revision
        microcode.loaded = true
        return true
    }
    
    log.info("Microcode: Current revision 0x%X", current_rev)
    
    wrmsr(MSR_IA32_UCODE_WRITE, u64(microcode.size))
    
    data_ptr := cast(u64)(microcode.data)
    wrmsr(MSR_IA32_UCODE_WRITE, data_ptr)
    
    current = rdmsr(MSR_IA32_UCODE_REV)
    current_rev = u32(current & 0xFFFFFFFF)
    
    if current_rev == update_revision || current_rev != 0 {
        microcode.revision = current_rev
        microcode.loaded = true
        return true
    }
    
    return false
}

load_amd_microcode :: proc() -> bool {
    if !has_cpuid(0x80000001, 0) {
        log.warn("Microcode: Extended CPUID not supported")
        return false
    }
    
    header := cast(^Microcode_Header)(microcode.data)
    update_revision := header.update_revision
    
    log.info("Microcode: Loading AMD revision 0x%X", update_revision)
    
    data_size := u64(microcode.size)
    data_addr := cast(u64)(microcode.data)
    
    for try_count := 0; try_count < 3; try_count += 1 {
        wrmsr(MSR_AMD_UCODE_UPDATE_ADDR, data_size)
        wrmsr(MSR_AMD_UCODE_UPDATE_DATA, data_addr)
        
        current := rdmsr(MSR_AMD_UCODE_UPDATE_STATUS)
        
        if u32(current & 0xFFFFFFFF) == update_revision {
            log.info("Microcode: Loaded revision 0x%X", update_revision)
            microcode.revision = update_revision
            microcode.loaded = true
            return true
        }
    }
    
    log.warn("Microcode: Failed to load")
    return false
}

get_microcode_revision :: proc() -> u32 {
    if info.vendor == .Intel {
        return u32(rdmsr(MSR_IA32_UCODE_REV) & 0xFFFFFFFF)
    } else if info.vendor == .AMD {
        return u32(rdmsr(MSR_AMD_UCODE_UPDATE_STATUS) & 0xFFFFFFFF)
    }
    return 0
}

is_microcode_loaded :: proc() -> bool {
    return microcode.loaded
}

Thermal_Init :: proc() {
    if info.vendor == .VM_QEMU || info.vendor == .VM_VMware {
        return
    }
    
    if !info.capabilities.has_mca {
        return
    }
    
    log.info("CPU Thermal: Initializing...")
}

thermal_read_status :: proc() -> u64 {
    if info.vendor == .Intel {
        return rdmsr(MSR_IA32_THERMAL_STATUS)
    } else if info.vendor == .AMD {
        return rdmsr(MSR_AMD_TEMPERATURE)
    }
    return 0
}

thermal_get_temperature :: proc() -> i32 {
    status := thermal_read_status()
    
    if info.vendor == .Intel {
        temp := (status >> 16) & 0x7F
        return i32(temp)
    }
    
    return 0
}

Frequency_Init :: proc() {
    log.info("CPU Frequency: Initializing...")
    
    if info.vendor == .VM_QEMU || info.vendor == .VM_VMware {
        log.info("CPU Frequency: VM detected - using emulated frequency")
        return
    }
    
    if info.vendor == .AMD {
        init_amd_pstates()
    } else {
        init_intel_pstates()
    }
}

init_intel_pstates :: proc() {
    _, _, _, edx := cpuid(6, 0)
    
    if (edx & (1 << 1)) != 0 {
        log.info("CPU Frequency: P-states supported")
    }
}

init_amd_pstates :: proc() {
    has_pstates := has_cpuid(0x80000007, 0)
    
    if !has_pstates {
        log.info("CPU Frequency: P-states not supported")
        return
    }
    
    _, _, _, edx := cpuid(0x80000007, 0)
    
    if (edx & (1 << 1)) != 0 {
        log.info("CPU Frequency: HW P-states supported")
    }
}

Frequency_Get :: proc() -> u32 {
    if !info.capabilities.has_tsc {
        return 0
    }
    
    tsc := intrinsics.read_tsc()
    intrinsics.sleep(1)
    tsc_end := intrinsics.read_tsc()
    
    diff := tsc_end - tsc
    
    return u32(diff / 1000000)
}

set_amd_frequency :: proc(mhz: u32) -> bool {
    if !has_cpuid(0x80000007, 0) {
        return false
    }
    
    pstate_disable := rdmsr(0xC0010071)
    
    if (pstate_disable & (1 << 63)) != 0 {
        wrmsr(0xC0010071, pstate_disable & 0x7FFFFFFFFFFFFFFF)
    }
    
    num_pstates := u8(8)
    best_idx: u8 = 0
    best_freq: u32 = 0
    
    for i: u8 = 0; i < num_pstates; i += 1 {
        msr_addr := u32(MSR_AMD_PSTATE_0) + u32(i)
        pstate := rdmsr(msr_addr)
        
        if (pstate & (1 << 63)) == 0 {
            fid := u32(pstate & 0x3F)
            did := u32((pstate >> 6) & 7)
            cpu_div := u32((pstate >> 8) & 0x1F)
            
            if did == 0 {
                continue
            }
            
            freq := (fid * 200 * 1000) / (did << cpu_div)
            
            if freq <= mhz && freq > best_freq {
                best_freq = freq
                best_idx = i
            }
        }
    }
    
    if best_freq == 0 {
        return false
    }
    
    wrmsr(MSR_AMD_P_STATE_CONTROL, u64(best_idx))
    
    return true
}

CState_Init :: proc() {
    log.info("CPU Idle: Initializing C-states...")
    
    if info.vendor == .VM_QEMU || info.vendor == .VM_VMware {
        log.info("CPU Idle: VM detected - ACPI-based idle")
        return
    }
    
    if info.vendor == .AMD {
        init_amd_cstates()
    } else if info.vendor == .Intel {
        init_intel_cstates()
    }
}

init_intel_cstates :: proc() {
    max_cstate := info.capabilities.max_cstate
    
    log.info("CPU Idle: Intel C-states (max C%d)", max_cstate)
}

init_amd_cstates :: proc() {
    max_cstate := info.capabilities.max_cstate
    
    log.info("CPU Idle: AMD C-states (max C%d)", max_cstate)
}

cstate_enter :: proc(cstate: u32) {
    #partial
    switch cstate {
    case 0:
        intrinsics.hlt()
    case 1:
        if info.capabilities.has_mwait {
            intrinsics.mwait(1, 0)
        } else {
            intrinsics.hlt()
        }
    case 2:
        if info.capabilities.has_mwait {
            intrinsics.mwait(2, 0)
        }
    case 3:
        intrinsics.hlt()
    }
}

cstate_get_current :: proc() -> u32 {
    if info.vendor == .AMD {
        if has_cpuid(0x80000007, 0) {
            return 1
        }
    }
    return 0
}

Performance_Counter_Init :: proc() {
    if perf_info.number_of_counters == 0 {
        return
    }
    
    pmu_reset()
    pmu_global_enable()
    
    log.info("Performance Counters: Initialized")
}

has_mwait :: proc() -> bool {
    return info.capabilities.has_mwait
}

has_rtm :: proc() -> bool {
    return info.capabilities.has_rtm
}

get_cpu_type :: proc() -> CPU_Type {
    return info.type
}

get_logical_cores :: proc() -> u8 {
    return info.logical_per_package
}

get_physical_cores :: proc() -> u8 {
    return info.cores_per_package
}

is_hyperthreading_enabled :: proc() -> bool {
    return info.threads_per_core > 1
}

get_topology_string :: proc() -> string {
    return string("N/A")
}