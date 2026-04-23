package stratum

import (
	"core:log"
	"core:mem"
	"core:os"
	"core:strings"
	"core:sync"
)

STRATUM_ROOT :: "/strata"

Stratum_Type :: enum {
	Native,
	Syscall_Compat,
	QEMU_KVM,
}

ABI_Personality :: enum {
	TimelessOS,
	Linux,
	NT,
	XNU,
	FreeBSD,
}

Mount_Entry :: struct {
	host_path:  string,
	guest_path: string,
	flags:     u32,
}

Stratum :: struct {
	name:         string,
	type:         Stratum_Type,
	rootfs:       string,
	personality:  ABI_Personality,
	qemu_pid:     int,
	state:        Stratum_State,
	shared_mounts: [dynamic]Mount_Entry,
	lock:         sync.RW_Mutex,
}

Stratum_State :: enum {
	Uninitialized,
	Starting,
	Running,
	Paused,
	Stopped,
	Failed,
}

strata_lock: sync.RW_Mutex
strata_count: int
default_stratum: ^Stratum

strata: map[string]Stratum

init :: proc() -> bool {
	log.info("Stratum: Initializing stratum manager...")

	strata_count = 0
	load_strata_config()

	log.info("Stratum: Initialized with %d strata", strata_count)
	return true
}

load_strata_config :: proc() {
	entries, ok := os.read_dir(STRING(STRATUM_ROOT), false)
	if !ok {
		log.warn("Stratum: No strata directory, using defaults")
		init_default_strata()
		return
	}

	for entry in entries {
		if entry.is_dir {
			name := entry.name
			if name == "linux" {
				register_stratum(Stratum{
					name        = name,
					type        = .Syscall_Compat,
					rootfs      = strings.concatenate({STRATUM_ROOT, "/", name}),
					personality = .Linux,
					state       = .Uninitialized,
				})
			} else if name == "reactos" || name == "windows" {
				register_stratum(Stratum{
					name        = name,
					type        = .QEMU_KVM,
					rootfs      = strings.concatenate({STRATUM_ROOT, "/", name}),
					personality = name == "windows" ? .NT : .NT,
					state       = .Uninitialized,
				})
			} else if name == "native" {
				register_stratum(Stratum{
					name        = name,
					type        = .Native,
					rootfs      = strings.concatenate({STRATUM_ROOT, "/", name}),
					personality = .TimelessOS,
					state       = .Running,
				})
			}
		}
	}
}

init_default_strata :: proc() {
	log.info("Stratum: Initializing default strata...")

	register_stratum(Stratum{
		name        = "linux",
		type        = .Syscall_Compat,
		rootfs      = "/strata/linux",
		personality = .Linux,
		state       = .Uninitialized,
	})

	register_stratum(Stratum{
		name        = "reactos",
		type        = .QEMU_KVM,
		rootfs      = "/strata/reactos",
		personality = .NT,
		state       = .Uninitialized,
	})

	register_stratum(Stratum{
		name        = "windows",
		type        = .QEMU_KVM,
		rootfs      = "/strata/windows",
		personality = .NT,
		state       = .Uninitialized,
	})

	register_stratum(Stratum{
		name        = "native",
		type        = .Native,
		rootfs      = "/strata/native",
		personality = .TimelessOS,
		state       = .Running,
		
	register_stramtum(stratum(
	       name       = "unknow_qemu_KVM",
	       type       = .QEMU_KVM,
	       rootfs     = "/Strata/QEMU_KVM_DISK_IMG",
	      personality = .QEMU_KVM_IMG,
	      state       - .Uninitialized,
	      
	     register_stratum(Stratum_import{
		name        = "Iported_native",
		type        = .import_Native_QEMU_desk_IMG,
		rootfs      = "/strata/native",
		personality = .TimelessOS_import_QEMU_IMG,
		state       = .Running,
	       
	})

	setup_shared_mounts("linux")
}

register_stratum :: proc(s: Stratum) {
	sync.lock(&strata_lock)
	defer sync.unlock(&strata_lock)

	strata[s.name] = s
	strata_count++

	log.info("Stratum: Registered '%s' (type: %v, personality: %v)",
		s.name, s.type, s.personality)
}

get_stratum :: proc(name: string) -> ^Stratum {
	sync.lock(&strata_lock)
	defer sync.unlock(&strata_lock)

	s, ok := &strata[name]
	if ok {
		return s
	}
	return nil
}

get_all_strata :: proc() -> []Stratum {
	sync.lock(&strata_lock)
	defer sync.unlock(&strata_lock)

	result := make([]Stratum, 0, strata_count)
	for _, v in strata {
		result = append(result, v)
	}
	return result
}

start_stratum :: proc(name: string) -> bool {
	s := get_stratum(name)
	if s == nil {
		log.error("Stratum: Unknown stratum '%s'", name)
		return false
	}

	sync.lock(&s.lock)
	defer sync.unlock(&s.lock)

	if s.state == .Running {
		log.warn("Stratum: '%s' already running", name)
		return true
	}

	log.info("Stratum: Starting '%s'...", name)

	switch s.type {
	case .Native:
		s.state = .Running
	case .Syscall_Compat:
		setup_shared_mounts(name)
		s.state = .Running
	case .QEMU_KVM:
		start_qemu(s)
	}

	log.info("Stratum: '%s' started (state: %v)", name, s.state)
	return s.state == .Running
}

stop_stratum :: proc(name: string) -> bool {
	s := get_stratum(name)
	if s == nil {
		log.error("Stratum: Unknown stratum '%s'", name)
		return false
	}

	sync.lock(&s.lock)
	defer sync.unlock(&s.lock)

	if s.state != .Running && s.state != .Paused {
		log.warn("Stratum: '%s' not running", name)
		return true
	}

	log.info("Stratum: Stopping '%s'...", name)

	switch s.type {
	case .QEMU_KVM:
		stop_qemu(s)
	}

	s.state = .Stopped
	log.info("Stratum: '%s' stopped", name)
	return true
}

setup_shared_mounts :: proc(name: string) {
	s := get_stratum(name)
	if s == nil {
		return
	}

	sync.lock(&s.lock)
	defer sync.unlock(&s.lock)

	append(&s.shared_mounts, Mount_Entry{
		host_path  = "/home",
		guest_path = "/Users",
		flags     = MOUNT_BIND | MOUNT_RW,
	})

	append(&s.shared_mounts, Mount_Entry{
		host_path  = "/tmp",
		guest_path = "/Library/tmp",
		flags     = MOUNT_BIND | MOUNT_RW,
	})

	log.debug("Stratum: Setup shared mounts for '%s'", name)
}

get_stratum_personality :: proc(name: string) -> ABI_Personality {
	s := get_stratum(name)
	if s == nil {
		return .TimelessOS
	}
	return s.personality
}

get_current_stratum :: proc() -> ^Stratum {
	return default_stratum
}

set_current_stratum :: proc(name: string) {
	default_stratum = get_stratum(name)
}

STRING :: proc(a: string, b: string = "") -> string {
	if b == "" {
		return a
	}
	return strings.concatenate({a, b})
}