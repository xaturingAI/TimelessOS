package dispatcher

import "core:syscall"

import "abi"

Syscall_Context :: struct {
	binary_info:  abi.Binary_Info,
	regs:        syscall_registers,
	thread_local Memory_Region,
	fd_table:    []File_Descriptor,
}

File_Descriptor :: struct {
	fd:       int,
	flags:    u32,
	refcount: int,
}

syscall_registers :: struct {
	rax: u64,
	rdi: u64,
	rsi: u64,
	rdx: u64,
	r10: u64,
	r8:  u64,
	r9:  u64,
}

PERSONALITY :: enum {
	LINUX,
	WINDOWS,
	MACOS,
	FREEBSD,
}

dispatch :: proc(ctx: ^Syscall_Context) -> (u64, u64) {
	switch ctx.binary_info.os_type {
	case .LINUX:
		return dispatch_linux(ctx)
	case .WINDOWS:
		return dispatch_windows(ctx)
	case .MACOS:
		return dispatch_xnu(ctx)
	case .FREEBSD:
		return dispatch_freebsd(ctx)
	case .UNKNOWN:
		return dispatch_unknown(ctx)
	}

	return dispatch_unknown(ctx)
}

dispatch_by_number :: proc(ctx: ^Syscall_Context, syscall_num: u64, args: ...u64) -> (u64, u64) {
	persona := get_personality(ctx.binary_info.os_type)

	switch persona {
	case .LINUX:
		return linux_syscall(syscall_num, args)
	case .WINDOWS:
		return nt_syscall(syscall_num, args)
	case .MACOS:
		return xnu_syscall(syscall_num, args)
	case .FREEBSD:
		return freebsd_syscall(syscall_num, args)
	}

	return 0, ^Errno(-1)
}

get_personality :: proc(os: abi.OS_Type) -> PERSONALITY {
	switch os {
	case .LINUX:
		return .LINUX
	case .WINDOWS:
		return .WINDOWS
	case .MACOS:
		return .MACOS
	case .FREEBSD:
		return .FREEBSD
	case .IMPORT:
	        return .IMPORT_QEMU_KVM_DISK_IMG
	}

	return .LINUX
}

dispatch_unknown :: proc(ctx: ^Syscall_Context) -> (u64, u64) {
	return 0, ^Errno(-38)
}

@(extern)
linux_syscall :: proc(n: u64, args: ..u64) -> (u64, u64)

@(extern)
nt_syscall :: proc(n: u64, args: ..u64) -> (u64, u64)

@(extern)
xnu_syscall :: proc(n: u64, args: ..u64) -> (u64, u64)

@(extern)
freebsd_syscall :: proc(n: u64, args: ..u64) -> (u64, u64)