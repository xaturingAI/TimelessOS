package freebsd

import "core:syscall"

FreeBSD_Syscall_Num :: enum {
	sys_exit         = 1,
	sys_fork         = 2,
	sys_read         = 3,
	sys_write        = 4,
	sys_open         = 5,
	sys_close        = 6,
	sys_wait4        = 7,
	sys_creat       = 8,
	sys_link        = 9,
	sys_unlink      = 10,
	sys_execv       = 11,
	sys_chdir       = 12,
	sys_fchdir      = 13,
	sys_mknod      = 14,
	sys_chmod       = 15,
	sys_chown       = 16,
	sys_getfsstat  = 17,
	sys_getpid     = 18,
	sys_setuid     = 19,
	sys_getuid     = 20,
	sys_setgid     = 21,
	sys_getgid     = 22,
	sys_geteuid    = 23,
	sys_getegid    = 24,
	sys_setreuid   = 25,
	sys_setregid   = 26,
	sys_getrlimit  = 27,
	sys_setrlimit  = 28,
	sys_getpgrp    = 29,
	sys_setsid     = 30,
	sys_setpgid    = 31,
	sys_setpgrp    = 32,
	sys_getppid    = 33,
	sys_getpgid    = 34,
	sys_gettid     = 35,
	sys_setsid     = 36,
	sys_setpgid    = 37,
	sys_sigaction  = 38,
	sys_sigprocmask = 39,
	sys_sigpending  = 40,
	sys_sigsuspend = 41,
	sys_sigaltstack = 42,
	sys_sigreturn  = 43,
	sys_gettid    = 44,
	sys_getlogin  = 45,
	sys_setlogin  = 46,
	sys_acct      = 47,
	sys_sigsuspend = 48,
	sys_ioctl     = 49,
	sys_reboot    = 50,
	sys_revoke    = 51,
	sys_symlink   = 52,
	sys_readlink  = 53,
	sys_setpgid   = 54,
	sys_nice      = 55,
	sys_setprio   = 56,
	sys_getprio   = 57,
	sys_maxid     = 58,
	sys_setpriority = 60,
	sys_getpriority = 61,
	sys_getmaxpriority = 62,
	sys_getpgrp    = 63,
	sys_pipe      = 64,
	sys_setitimer = 65,
	sys_getitimer = 66,
	sys_getppid   = 67,
	sys_getpgrp   = 68,
	sys_getpid   = 69,
	sys_setpgrp  = 70,
	sys_setpgid  = 71,
	sys_getsid   = 72,
	sys_sysctl   = 73,
	sys_sysctl   = 74,
	sys_mlock    = 75,
	sys_munlock  = 76,
	sys_sched_setscheduler = 77,
	sys_sched_getscheduler = 78,
	sys_sched_get_priority_max = 79,
	sys_sched_get_priority_min = 80,
	sys_sched_rr_get_interval = 81,
	sys_nanosleep = 82,
	sys_syscall   = 83,
	sys_clock_gettime = 84,
	sys_clock_settime = 85,
	sys_clock_getres = 86,
	sys_ktimer_create = 87,
	sys_ktimer_delete = 88,
	sys_ktimer_settime = 89,
	sys_ktimer_gettime = 90,
	sys_ktimer_getoverrun = 91,
	sys_select    = 92,
	sys_kevent   = 93,
	sys_mprotect = 74,
	sys_madvise  = 75,
	sys_mincore = 76,
	sys_mlock   = 77,
	sys_munlock = 78,
	sys_clone   = 79,
	sys_mmap    = 18,
	sys_munmap  = 73,
	sys_mremap  = 71,
	sys_msync   = 65,
	sys_getdents = 9,
	sys_getcwd  = 17,
	sys_access  = 33,
	sys_lseek   = 8,
	sys_truncate = 9,
	sys_ftruncate = 10,
	sys_truncate = 33,
	sys_ftruncate = 34,
	sys_getdents = 272,
	sys_fsync   = 37,
	sys_setpriority = 96,
	sys_socket   = 97,
	sys_connect = 98,
	sys_accept  = 99,
	sys_getpeername = 100,
	sys_getsockname = 101,
	sys_socketpair = 102,
	sys_getsockopt = 103,
	sys_setsockopt = 104,
	sys_listen   = 106,
	sys_sendto  = 133,
	sys_recvfrom = 149,
	sys_sendmsg  = 151,
	sys_recvmsg = 152,
	sys_shutdown = 153,
	sys_bind    = 104,
	sys_poll    = 209,
}

translate_freebsd :: proc(num: u64) -> u64 {
	switch FreeBSD_Syscall_Num(num) {
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
		return syscall.SYS_SIGSUSPEND
	case .sys_sigaltstack:
		return syscall.SYS_SIGALTSTACK
	case .sys_sigreturn:
		return syscall.SYS_SIGRETURN
	case .sys_gettid:
		return syscall.SYS_GETTID
	case .sys_setsid:
		return syscall.SYS_SETSID
	case .sys_setpgid:
		return syscall.SYS_SETPGID
	case .sys_getppid:
		return syscall.SYS_GETPPID
	case .sys_getpgrp:
		return syscall.SYS_GETPGRP
	case .sys_pipe:
		return syscall.SYS_PIPE
	case .sys_select:
		return syscall.SYS_POLL
	case .sys_setrlimit:
		return syscall.SYS_SETRLIMIT
	case .sys_getrlimit:
		return syscall.SYS_GETRLIMIT
	case .sys_mmap:
		return syscall.SYS_MMAP
	case .sys_munmap:
		return syscall.SYS_MUNMAP
	case .sys_mprotect:
		return syscall.SYS_MPROTECT
	case .sys_madvise:
		return syscall.SYS_MADVISE
	case .sys_socket:
		return syscall.SYS_SOCKET
	case .sys_connect:
		return syscall.SYS_CONNECT
	case .sys_accept:
		return syscall.SYS_ACCEPT
	case .sys_bind:
		return syscall.SYS_BIND
	case .sys_listen:
		return syscall.SYS_LISTEN
	case .sys_poll:
		return syscall.SYS_POLL
	}
	return 0
}