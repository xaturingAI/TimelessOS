package userspace

import "core:mem"
import "core:log"
import "core:sync"

import "abi"
import "dispatcher"
import "compat/linux"
import "compat/nt"
import "compat/xnu"
import "compat/freebsd"
import "filesystem/vfs"   // strata VFS — for path translation

// ============================================================
// PID allocator  (simple bump allocator — replace with bitmap
// once you have a proper process table)
// ============================================================

@(private)
_next_pid: u32 = 1

@(private)
_pid_lock: sync.Mutex

alloc_pid :: proc() -> u32 {
	sync.mutex_lock(&_pid_lock)
	defer sync.mutex_unlock(&_pid_lock)
	pid := _next_pid
	_next_pid += 1
	return pid
}

// ============================================================
// File Descriptor Table
// Each process has its own fd table.
// fd 0/1/2 = stdin/stdout/stderr — pre-populated on create.
// ============================================================

MAX_FDS :: 1024

FD_Entry :: struct {
	file:   ^vfs.VFS_FILE,
	flags:  u32,
	valid:  bool,
}

FD_Table :: struct {
	entries: [MAX_FDS]FD_Entry,
}

fd_alloc :: proc(table: ^FD_Table, file: ^vfs.VFS_FILE) -> int {
	for i in 3..<MAX_FDS {   // start at 3 — 0/1/2 are stdio
		if !table.entries[i].valid {
			table.entries[i] = FD_Entry{file = file, valid = true}
			return i
		}
	}
	return -1  // EMFILE
}

fd_get :: proc(table: ^FD_Table, fd: int) -> ^vfs.VFS_FILE {
	if fd < 0 || fd >= MAX_FDS do return nil
	if !table.entries[fd].valid  do return nil
	return table.entries[fd].file
}

fd_close :: proc(table: ^FD_Table, fd: int) -> bool {
	if fd < 0 || fd >= MAX_FDS        do return false
	if !table.entries[fd].valid        do return false
	table.entries[fd].valid = false
	table.entries[fd].file  = nil
	return true
}

// ============================================================
// CPU Register State
// Passed to every syscall handler so it can read/write args.
// Matches the x86_64 SYSCALL convention:
//   rax = syscall number
//   rdi, rsi, rdx, r10, r8, r9 = args 1-6
//   rax (on return) = return value
// ============================================================

CPU_State :: struct {
	rax: u64,   // syscall number on entry, return value on exit
	rdi: u64,   // arg 1
	rsi: u64,   // arg 2
	rdx: u64,   // arg 3
	r10: u64,   // arg 4  (NOTE: Linux uses r10 not rcx in SYSCALL)
	r8:  u64,   // arg 5
	r9:  u64,   // arg 6
	rip: u64,   // instruction pointer
	rsp: u64,   // stack pointer
	rflags: u64,
}

// ============================================================
// Process State
// ============================================================

Process_State :: enum u8 {
	Created  = 0,
	Running  = 1,
	Sleeping = 2,
	Zombie   = 3,
	Dead     = 4,
}

// ============================================================
// User_Process  (expanded from original bare struct)
// ============================================================

User_Process :: struct {
	// --- Identity ---
	pid:          u32,
	ppid:         u32,   // parent pid
	name:         string,

	// --- ABI / binary info ---
	binary_info:  abi.Binary_Info,
	ctx:          dispatcher.Syscall_Context,
	loaded:       bool,

	// --- Stratum ---
	// Which OS stratum this process belongs to.
	// Drives path translation on every VFS syscall.
	stratum_type: vfs.Stratum_Type,
	stratum_name: string,

	// If this process lives inside a QEMU guest, this points
	// to its image descriptor so the VFS layer can route I/O.
	qemu_image:   ^vfs.QEMU_Image,

	// --- Execution state ---
	state:        Process_State,
	cpu:          CPU_State,   // current register snapshot
	exit_code:    int,

	// --- Resources ---
	fd_table:     FD_Table,
	allocator:    mem.Allocator,
}

// ============================================================
// create  (was "init" — renamed to avoid shadowing core:init
// and because "init" in Odin is a reserved package init hook)
// ============================================================

create :: proc(
	data:         []byte,
	name:         string          = "unnamed",
	ppid:         u32             = 0,
	qemu_image:   ^vfs.QEMU_Image = nil,
	allocator:    mem.Allocator   = context.allocator,
) -> (User_Process, bool) {

	// Need at least 64 bytes to detect the binary header
	if len(data) < 64 {
		log.error("userspace.create: binary too small to detect format")
		return {}, false
	}

	info := abi.detect(data[:64])

	if info.binary_type == .UNKNOWN {
		log.error("userspace.create: failed to detect binary format")
		return {}, false
	}

	log.infof("userspace.create: binary=%v os=%v arch=%v name=%v",
		info.binary_type, info.os_type, info.arch, name)

	// Map ABI OS type -> Stratum_Type so VFS knows which path
	// translation table to use for every syscall this process makes.
	stype, sname := abi_os_to_stratum(info.os_type, qemu_image)

	// Fixed: was named "proc" which is a reserved keyword in Odin.
	// Renamed to "process" throughout.
	process := User_Process{
		pid          = alloc_pid(),
		ppid         = ppid,
		name         = name,
		binary_info  = info,
		loaded       = true,
		stratum_type = stype,
		stratum_name = sname,
		qemu_image   = qemu_image,
		state        = .Created,
		allocator    = allocator,
	}

	process.ctx.binary_info = info

	// Wire the FD table's stdio stubs (0=stdin 1=stdout 2=stderr).
	// Real impl would point these at console VFS nodes.
	process.fd_table.entries[0] = FD_Entry{valid = true}  // stdin
	process.fd_table.entries[1] = FD_Entry{valid = true}  // stdout
	process.fd_table.entries[2] = FD_Entry{valid = true}  // stderr

	log.infof("userspace.create: pid=%v stratum=%v (%v)",
		process.pid, process.stratum_type, process.stratum_name)

	return process, true
}

// ============================================================
// destroy  — clean up all resources owned by a process
// ============================================================

destroy :: proc(process: ^User_Process) {
	if process == nil do return

	log.infof("userspace.destroy: pid=%v name=%v", process.pid, process.name)

	// Close all open file descriptors
	for i in 0..<MAX_FDS {
		if process.fd_table.entries[i].valid {
			fd_close(&process.fd_table, i)
		}
	}

	process.loaded = false
	process.state  = .Dead
}

// ============================================================
// execute  — dispatch a single syscall for a process
//
// CPU state is passed by pointer so the handler can write the
// return value directly into rax (matches hardware behaviour).
//
// Returns (result, errno) — errno == 0 means success.
// ============================================================

execute :: proc(process: ^User_Process, cpu: ^CPU_State) -> (result: u64, errno: u64) {
	if process == nil || !process.loaded {
		return 0, _errno(ENOSYS)
	}

	sysnum := cpu.rax
	args   := [6]u64{ cpu.rdi, cpu.rsi, cpu.rdx, cpu.r10, cpu.r8, cpu.r9 }

	// Before dispatching, translate any path arguments so the
	// underlying VFS always sees TimelessOS canonical paths.
	// (Path args live in rdi/rsi depending on syscall — the compat
	// layers handle the exact slot; we set context here.)
	process.ctx.stratum_type  = process.stratum_type
	process.ctx.qemu_image    = process.qemu_image

	switch process.binary_info.os_type {
	case .LINUX:
		translated := linux.translate_syscall(sysnum)
		result, errno = dispatcher.dispatch_by_number(&process.ctx, translated, ..args[:])

	case .WINDOWS:
		// NT syscalls pass the syscall number in eax but use a
		// different stack-based calling convention — translate
		// Windows path args (C:\...) before dispatch.
		nt_path_fixup(cpu, process)
		translated := nt.translate_nt_native(sysnum)
		result, errno = dispatcher.dispatch_by_number(&process.ctx, translated, ..args[:])

	case .MACOS:
		translated := xnu.translate_xnu(sysnum)
		result, errno = dispatcher.dispatch_by_number(&process.ctx, translated, ..args[:])

	case .FREEBSD:
		translated := freebsd.translate_freebsd(sysnum)
		result, errno = dispatcher.dispatch_by_number(&process.ctx, translated, ..args[:])

	case .NATIVE:
		// TimelessOS native binary — no translation needed
		result, errno = dispatcher.dispatch_by_number(&process.ctx, sysnum, ..args[:])

	case:
		log.errorf("userspace.execute: unknown OS type %v for pid=%v",
			process.binary_info.os_type, process.pid)
		return 0, _errno(ENOSYS)
	}

	// Write return value back into rax so the CPU state is consistent
	cpu.rax = result
	return result, errno
}

// ============================================================
// Path translation helpers
// Called before dispatching syscalls that carry path arguments.
// The strata VFS translate_to_host proc does the heavy lifting.
// ============================================================

// For NT syscalls: rdi typically holds a pointer to a
// UNICODE_STRING / OBJECT_ATTRIBUTES. Since we can't dereference
// user pointers here safely, we tag the context so the nt compat
// layer can call vfs.nt_path_to_internal on the string it reads.
nt_path_fixup :: proc(cpu: ^CPU_State, process: ^User_Process) {
	process.ctx.needs_nt_path_fixup = true
}

// Translate a guest-side path string to TimelessOS canonical form.
// Call this from inside a compat layer when handling a path syscall.
resolve_path_for_process :: proc(process: ^User_Process, guest_path: string) -> string {
	if process.stratum_type == .NT_Windows {
		// Convert C:\... to /C/... then through the layout map
		internal := vfs.nt_path_to_internal(guest_path)
		return vfs.translate_to_host(internal, process.stratum_type)
	}
	return vfs.translate_to_host(guest_path, process.stratum_type)
}

// ============================================================
// Stratum mapping helper
// ============================================================

abi_os_to_stratum :: proc(
	os: abi.OS_Type,
	qemu: ^vfs.QEMU_Image,
) -> (vfs.Stratum_Type, string) {

	// If the process comes from a QEMU image, mark it as a
	// QEMU guest regardless of detected OS — the image provides
	// the full environment.
	if qemu != nil {
		return .QEMU_Guest, "qemu-guest"
	}

	switch os {
	case .LINUX:   return .Linux,      "linux"
	case .WINDOWS: return .NT_Windows, "nt-windows"
	case .MACOS:   return .XNU_MacOS,  "xnu-macos"
	case .FREEBSD: return .FreeBSD,    "freebsd"
	case .NATIVE:  return .Native,     "native"
	case:          return .Native,     "native"
	}
}

// ============================================================
// Errno helpers
// Linux-style: error return is the negated errno value cast to u64
// so that callers can check  errno != 0  for failure.
// ============================================================

ENOSYS  :: u64(38)   // function not implemented
EBADF   :: u64(9)    // bad file descriptor
ENOMEM  :: u64(12)   // out of memory
EFAULT  :: u64(14)   // bad address
EINVAL  :: u64(22)   // invalid argument
EMFILE  :: u64(24)   // too many open files

// _errno returns the negated errno packed into u64
// e.g. _errno(ENOSYS) == 0xFFFFFFFFFFFFFFDA  (same as Linux -38)
_errno :: #force_inline proc(e: u64) -> u64 {
	return ~e + 1   // two's complement negation
}

// ============================================================
// Accessors (convenience for the scheduler / kernel)
// ============================================================

process_is_alive :: proc(process: ^User_Process) -> bool {
	return process != nil &&
	       process.loaded &&
	       process.state != .Dead &&
	       process.state != .Zombie
}

process_set_state :: proc(process: ^User_Process, state: Process_State) {
	if process == nil do return
	log.debugf("userspace: pid=%v state %v -> %v",
		process.pid, process.state, state)
	process.state = state
}
