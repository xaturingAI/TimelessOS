package linux

import "core:syscall"

import "../dispatcher"

Linux_Syscall_Num :: enum {
	read           = 0,
	write          = 1,
	open           = 2,
	close          = 3,
	stat           = 4,
	fstat          = 5,
	lstat         = 6,
	poll          = 7,
	lseek         = 8,
	mmap          = 9,
	mprotect      = 10,
	munmap        = 11,
	brk           = 12,
	rt_sigaction  = 13,
	rt_sigprocmask = 14,
	rt_sigreturn  = 15,
	ioctl         = 16,
	pread64       = 17,
	pwrite64      = 18,
	readv         = 19,
	writev        = 20,
	access        = 21,
	pipe          = 22,
	select       = 23,
	sched_yield  = 24,
	mremap       = 25,
	msync        = 26,
	mincore      = 27,
	madvise      = 28,
	shmget       = 29,
	shmat        = 30,
	shmctl       = 31,
	dup          = 32,
	dup2         = 33,
	pause        = 34,
	nanosleep    = 35,
	getitimer    = 36,
	alarm        = 37,
	setitimer    = 38,
	getpid       = 39,
	getuid       = 40,
	alarm       = 41,
	waitpid      = 42,
	socket       = 43,
	connect      = 44,
	accept       = 45,
	bind         = 46,
	listen       = 47,
	getsockname  = 48,
	getpeername  = 49,
	socketpair   = 50,
	send         = 51,
	sendto       = 52,
	recv         = 53,
	recvfrom     = 54,
	shutdown    = 55,
	setsockopt   = 56,
	getsockopt   = 57,
	clone        = 58,
	fork         = 59,
	vfork        = 60,
	execve       = 61,
	exit         = 62,
	wait4        = 63,
	kill         = 64,
	uname        = 65,
	semget       = 66,
	semop        = 67,
	semctl       = 68,
	shmdt        = 69,
	msgget       = 70,
	msgsnd       = 71,
	msgrcv       = 72,
	msgctl       = 73,
	msgget       = 74,
	fcntl        = 75,
	flock        = 76,
	fsync        = 77,
 fdatasync    = 78,
	truncate     = 79,
	ftruncate   = 80,
	getdents     = 81,
	getcwd       = 82,
	chdir        = 83,
	renamed      = 84,
	mkdir        = 85,
	rmdir        = 86,
	creat        = 87,
	link         = 88,
	unlink       = 89,
	symlink      = 90,
	readlink     = 91,
	chmod        = 92,
	fchmod       = 93,
	chown        = 94,
	fchown       = 95,
	lchown       = 96,
	umask        = 97,
	gettimeofday = 98,
	getrlimit    = 99,
	getrusage    = 100,
	sysinfo      = 101,
	times        = 102,
	getppid      = 103,
	getpgrp      = 104,
	setsid       = 105,
	setpgid      = 106,
	getgid       = 107,
	setgid       = 108,
	geteuid      = 109,
	seteuid      = 110,
	getegid      = 111,
	setegid      = 112,
	getpgid      = 113,
	setfsuid     = 114,
	setfsgid     = 115,
	getsid       = 116,
	capget       = 117,
	capset       = 118,
	rt_sigpending = 119,
	rt_sigtimedwait = 120,
	rt_sigqueueinfo = 121,
	rt_sigsuspend = 122,
	sigaltstack  = 123,
	utime        = 124,
	mknod        = 125,
	uselib       = 126,
	personality = 127,
	ustat        = 128,
	statfs       = 129,
	fstatfs      = 130,
	sysfs       = 131,
	getpriority = 132,
	setpriority = 133,
	setregid     = 134,
	getregid     = 135,
	prctl        = 136,
	arch_prctl  = 137,
	adjtimex    = 138,
	setrlimit    = 139,
	chroot      = 140,
	sync        = 141,
	acct        = 142,
	settimeofday = 143,
	mount       = 144,
	umount2     = 145,
	swapoff     = 146,
	swapon      = 147,
	reboot      = 148,
	sethostname = 149,
	setdomainname = 150,
	iopl        = 151,
	ioperm      = 152,
	init_module = 153,
	delete_module = 154,
	quotactl    = 155,
	gettid      = 156,
	reparent    = 157,
	setns       = 158,
	uname       = 159,
}

Syscall_Map :: map[u64]proc() -> u64

translate_syscall :: proc(num: u64) -> u64 {
	switch Linux_Syscall_Num(num) {
	case .read:
		return syscall.SYS_READ
	case .write:
		return syscall.SYS_WRITE
	case .open:
		return syscall.SYS_OPEN
	case .close:
		return syscall.SYS_CLOSE
	case .mmap:
		return syscall.SYS_MMAP
	case .mprotect:
		return syscall.SYS_MPROTECT
	case .munmap:
		return syscall.SYS_MUNMAP
	case .brk:
		return syscall.SYS_BRK
	case .rt_sigaction:
		return syscall.SYS_RT_SIGACTION
	case .rt_sigprocmask:
		return syscall.SYS_RT_SIGPROCMASK
	case .rt_sigreturn:
		return syscall.SYS_RT_SIGRETURN
	case .ioctl:
		return syscall.SYS_IOCTL
	case .pread64:
		return syscall.SYS_PREAD64
	case .pwrite64:
		return syscall.SYS_PWRITE64
	case .stat:
		return syscall.SYS_STAT
	case .fstat:
		return syscall.SYS_FSTAT
	case .lstat:
		return syscall.SYS_LSTAT
	case .poll:
		return syscall.SYS_POLL
	case .lseek:
		return syscall.SYS_SEEK
	case .getpid:
		return syscall.SYS_GETPID
	case .getuid:
		return syscall.SYS_GETUID
	case .getgid:
		return syscall.SYS_GETGID
	case .setuid:
		return syscall.SYS_SETUID
	case .setgid:
		return syscall.SYS_SETGID
	case .getpid:
		return syscall.SYS_GETPID
	case .fork:
		return syscall.SYS_FORK
	case .clone:
		return syscall.SYS_CLONE
	case .execve:
		return syscall.SYS_EXECVE
	case .exit:
		return syscall.SYS_EXIT
	case .wait4:
		return syscall.SYS_WAIT4
	case .kill:
		return syscall.SYS_KILL
	case .uname:
		return syscall.SYS_UNAME
	case .socket:
		return syscall.SYS_SOCKET
	case .connect:
		return syscall.SYS_CONNECT
	case .accept:
		return syscall.SYS_ACCEPT
	case .bind:
		return syscall.SYS_BIND
	case .listen:
		return syscall.SYS_LISTEN
	case .pipe:
		return syscall.SYS_PIPE
	case .getsockname:
		return syscall.SYS_GETSOCKNAME
	case .getpeername:
		return syscall.SYS_GETPEERNAME
	case .socketpair:
		return syscall.SYS_SOCKETPAIR
	case .send:
		return syscall.SYS_SEND
	case .sendto:
		return syscall.SYS_SENDTO
	case .recv:
		return syscall.SYS_RECV
	case .recvfrom:
		return syscall.SYS_RECVFROM
	case .shutdown:
		return syscall.SYS_SHUTDOWN
	case .setsockopt:
		return syscall.SYS_SETSOCKOPT
	case .getsockopt:
		return syscall.SYS_GETSOCKOPT
	case .getppid:
		return syscall.SYS_GETPPID
	case .getpgrp:
		return syscall.SYS_GETPGRP
	case .setsid:
		return syscall.SYS_SETSID
	case .setpgid:
		return syscall.SYS_SETPGID
	case .geteuid:
		return syscall.SYS_GETEUID
	case .setegid:
		return syscall.SYS_SETEGID
	case .getegid:
		return syscall.SYS_GETEGID
	case .getpriority:
		return syscall.SYS_GETPRIORITY
	case .setpriority:
		return syscall.SYS_SETPRIORITY
	case .setrlimit:
		return syscall.SYS_SETRLIMIT
	case .getrlimit:
		return syscall.SYS_GETRLIMIT
	case .getrusage:
		return syscall.SYS_GETRUSAGE
	case .gettimeofday:
		return syscall.SYS_GETTIMEOFDAY
	case .sysinfo:
		return syscall.SYS_SYSINFO
	case .times:
		return syscall.SYS_TIMES
	case .adjtimex:
		return syscall.SYS_ADJTIMEX
	case .sync:
		return syscall.SYS_SYNC
	case .mount:
		return syscall.SYS_MOUNT
	case .umount2:
		return syscall.SYS_UMOUNT2
	case .mknod:
		return syscall.SYS_MKNOD
	case .chmod:
		return syscall.SYS_CHMOD
	case .fchmod:
		return syscall.SYS_FCHMOD
	case .chown:
		return syscall.SYS_CHOWN
	case .fchown:
		return syscall.SYS_FCHOWN
	case .lchown:
		return syscall.SYS_LCHOWN
	case .umask:
		return syscall.SYS_UMASK
	case .gettid:
		return syscall.SYS_GETTID
	case .setns:
		return syscall.SYS_SETNS
	}
	return 0
}