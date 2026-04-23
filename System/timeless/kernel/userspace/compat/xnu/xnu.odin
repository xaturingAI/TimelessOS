package xnu

import "core:syscall"

XNU_Syscall_Num :: enum {
	indirdirect      = 0,
	sys_nice         = 1,
	sys_thread_self  = 2,
	sys_proc_self    = 3,
	sys_proc_self_trap = 4,
	sys_syscall_root = 5,
	sys_exit         = 6,
	sys_fork         = 7,
	sys_read         = 8,
	sys_write        = 9,
	sys_open         = 10,
	sys_close        = 11,
	sys_wait4        = 12,
	sys_creat        = 13,
	sys_link         = 14,
	sys_unlink       = 15,
	sys_execv        = 16,
	sys_chdir        = 17,
	sys_fchdir       = 18,
	sys_mknod        = 19,
	sys_chmod        = 20,
	sys_chown        = 21,
	sys_getfsstat    = 22,
	sys_getpid      = 23,
	sys_setuid       = 24,
	sys_getuid       = 25,
	sys_geteuid      = 26,
	sys_setgid       = 27,
	sys_getgid       = 28,
	sys_getegid      = 29,
	sys_setreuid     = 30,
	sys_setregid     = 31,
	sys_getrlimit    = 32,
	sys_setrlimit    = 33,
	sys_getpgrp      = 34,
	sys_setpgrp      = 35,
	sys_setpgid      = 36,
	sys_getppid      = 37,
	sys_getpgid      = 38,
	sys_setsid       = 39,
	sys_setpgid      = 40,
	sys_sigaction    = 41,
	sys_sigprocmask  = 42,
	sys_sigpending   = 43,
	sys_sigsuspend   = 44,
	sys_sigaltstack  = 45,
	sys_sigreturn    = 46,
	sys_gettid       = 47,
	sys_setsid       = 48,
	sys_syscall     = 49,
	sys_semaphore_create = 50,
	sys_semaphore_destroy = 51,
	sys_semaphore_signal = 52,
	sys_semaphore_signal_all = 53,
	sys_semaphore_wait = 54,
	sys_semaphore_wait_signal = 55,
	sys_semaphore_timedwait = 56,
	sys_init_process = 57,
	sys_map_fd       = 58,
	sys_unmap_fd     = 59,
	sys_map_file    = 60,
	sys_unmap_file  = 61,
	sys_msync       = 62,
	sys_sysctl      = 63,
	sys_sysctlbyname = 64,
	sys_sysctlgetnext = 65,
	sys_sysctloid   = 66,
	sys_sysctloidname = 67,
	sys_malloc      = 68,
	sys_free        = 69,
	sys_malloc_gc   = 70,
	sys_mprotect    = 71,
	sys_madvise     = 72,
	sys_mincore     = 73,
	sys_mlock       = 74,
	sys_munlock     = 75,
	sys_getiovation  = 76,
	sys_collect_lost_rsrc = 77,
	sys_maxid       = 78,
}

translate_xnu :: proc(num: u64) -> u64 {
	switch XNU_Syscall_Num(num) {
	case .sys_read:
		return syscall.SYS_READ
	case .sys_write:
		return syscall.SYS_WRITE
	case .sys_open:
		return syscall.SYS_OPEN
	case .sys_close:
		return syscall.SYS_CLOSE
	case .sys_exit:
		return syscall.SYS_EXIT
	case .sys_fork:
		return syscall.SYS_FORK
	case .sys_wait4:
		return syscall.SYS_WAIT4
	case .sys_getpid:
		return syscall.SYS_GETPID
	case .sys_setuid:
		return syscall.SYS_SETUID
	case .sys_getuid:
		return syscall.SYS_GETUID
	case .sys_geteuid:
		return syscall.SYS_GETEUID
	case .sys_setgid:
		return syscall.SYS_SETGID
	case .sys_getgid:
		return syscall.SYS_GETGID
	case .sys_getegid:
		return syscall.SYS_GETEGID
	case .sys_sigaction:
		return syscall.SYS_SIGACTION
	case .sys_sigprocmask:
		return syscall.SYS_SIGPROCMASK
	case .sys_sigpending:
		return syscall.SYS_SIGPENDING
	case .sys_sigsuspend:
		return syscall.SIGSUSPEND
	case .sys_sigaltstack:
		return syscall.SYS_SIGALTSTACK
	case .sys_sigreturn:
		return syscall.SYS_SIGRETURN
	case .sys_gettid:
		return syscall.SYS_GETTID
	case .sys_setsid:
		return syscall.SYS_SETSID
	case .sys_mprotect:
		return syscall.SYS_MPROTECT
	case .sys_madvise:
		return syscall.SYS_MADVISE
	case .sys_mincore:
		return syscall.SYS_MINCORE
	case .sys_mlock:
		return syscall.SYS_MLOCK
	case .sys_munlock:
		return syscall.SYS_MUNLOCK
	case .sys_sysctl:
		return syscall.SYS_SYSCTL
	}
	return 0
}